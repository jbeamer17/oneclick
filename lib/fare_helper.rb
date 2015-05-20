class FareHelper

  #Check to see if we should calculate the fare locally or use a third-party service.
  def calculate_fare(trip_part, itinerary)
    #Check to see if this user is registered to book directly with this service
    service = Service.find(itinerary['service_id'])
    up = UserService.where(user_profile: trip_part.trip.user.user_profile, service: itinerary.service)
    if up.count > 0
      return query_fare(itinerary)
    else
      return calculate_fare_locally(trip_part, itinerary)
    end
  end

  #Caculate Fare based on stored fare rules
  def calculate_fare_locally(trip_part, itinerary)
    is_paratransit = itinerary.service.is_paratransit? rescue false

    if is_paratransit
      cost = itinerary.calculate_fare
      if cost
        itinerary.cost = cost
        itinerary.save
      end
    else
      my_fare = itinerary.service.fare_structures.where(fare_type: 0).order(:base).first

      if my_fare
        itinerary.cost = my_fare.base
        itinerary.cost_comments= my_fare.desc
      else
        itinerary.cost_comments = itinerary.service.fare_structures.where(fare_type: 2).pluck(:desc).first
      end

      itinerary.save
    end
  end

  #Get the fare from a third-party source (e.g., a booking agent.)
  def query_fare(itinerary)
    case itinerary.service.booking_service_code
    when 'ecolane'
      eh = EcolaneHelpers.new
      result, my_fare =  eh.query_fare(itinerary)
      if result
        itinerary.cost = my_fare
      end

      itinerary.save
    end
  end

  #Allows a global multiplier for fixed-route fare if a travler's age is greater than config.discount_fare_age AND config.discount_fare_active is true
  def calculate_fixed_route_fare(trip_part, itinerary)

    #Check for multipliers
    if Oneclick::Application.config.discount_fare_active and trip_part.trip.user.age and trip_part.trip.user.age > Oneclick::Application.config.discount_fare_age
      itinerary.cost *= Oneclick::Application.config.discount_fare_multiplier
      itinerary.save
    end

    #Check for comments.
    begin
      itinerary.cost_comments = itinerary.service.fare_structures.pluck(:desc).first
      itinerary.save
    rescue
      return
    end

  end

  def get_itinerary_cost itinerary
    estimated = false
    fare =  itinerary.cost || (itinerary.service.fare_structures.first rescue nil)
    price_formatted = nil
    cost_in_words = ''
    comments = ''
    is_paratransit = itinerary.service.is_paratransit? rescue false

    if is_paratransit
      para_fare = ParatransitItinerary.calculate_fare itinerary, itinerary.cost
      if para_fare
        estimated = para_fare[:estimated]
        fare = para_fare[:fare]
        price_formatted = para_fare[:price_formatted]
        cost_in_words = para_fare[:cost_in_words]
        comments = para_fare[:comments]
      end
    else
      if fare.respond_to? :fare_type
        case fare.fare_type
        when FareStructure::FLAT
          if fare.base and fare.rate
            estimated = true
            comments = "+#{number_to_currency(fare.rate)}/mile - " + I18n.t(:cost_estimated)
            fare = fare.base.to_f
            price_formatted = number_to_currency(fare.ceil) + '*'
            cost_in_words = number_to_currency(fare.ceil) + I18n.t(:est)
          elsif fare.base
            fare = fare.base.to_f
            price_formatted = number_to_currency(fare)
            cost_in_words = price_formatted
          else
            fare = nil
          end
        when FareStructure::MILEAGE
            if fare.base
              estimated = true
              comments = "+#{number_to_currency(fare.rate)}/mile - " + I18n.t(:cost_estimated)
              fare = fare.base.to_f
              price_formatted = number_to_currency(fare.ceil) + '*'
              cost_in_words = number_to_currency(fare.ceil) + I18n.t(:est)
            else
              fare = nil
            end
        when FareStructure::COMPLEX
          fare = nil
          estimated = true
          price_formatted = '*'
          comments = I18n.t(:see_details_for_cost)
          cost_in_words = I18n.t(:see_below)
        end
      else
        if itinerary.is_walk or itinerary.is_bicycle #TODO: walk, bicycle currently are put in transit category
          Rails.logger.info 'is walk or bicycle, so no charge'
          fare = 0
          price_formatted = I18n.t(:no_charge)
          cost_in_words = price_formatted
        else
          case itinerary.mode
          when Mode.taxi
            if fare
              fare = fare.ceil
              estimated = true
              price_formatted = number_to_currency(fare) + '*'
              comments = I18n.t(:cost_estimated)
              cost_in_words = number_to_currency(fare) + I18n.t(:est)
            end
          when Mode.rideshare
            fare = nil
            estimated = true
            price_formatted = '*'
            comments = I18n.t(:see_details_for_cost)
            cost_in_words = I18n.t(:see_below)
          end
        end
      end
    end

    if price_formatted.nil?
      unless fare.nil?
        fare = fare.to_f
        if fare == 0
          Rails.logger.info 'no charge as fare is 0'
          price_formatted = I18n.t(:no_charge)
          cost_in_words = price_formatted
        else
          price_formatted = number_to_currency(fare)
          cost_in_words = number_to_currency(fare)
        end
      else
        estimated = true
        price_formatted = '*'
        comments = I18n.t(:see_details_for_cost)
        cost_in_words = I18n.t(:unknown)
      end
    end

    # save calculated fare
    if !estimated && fare && itinerary.cost != fare
      itinerary.update_attributes(cost: fare)
    end

    return {price: fare, comments: comments, price_formatted: price_formatted, estimated: estimated, cost_in_words: cost_in_words}
  end
end