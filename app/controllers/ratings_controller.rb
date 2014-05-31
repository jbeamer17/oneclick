class RatingsController < ApplicationController

  def new
    if params[:trip_id]
      rateable = Trip.find(params[:trip_id])
      target = trip_ratings_path(rateable)
    elsif params[:agency_id]
      rateable = Agency.find(params[:agency_id])
      target = agency_ratings_path(rateable)
    elsif params[:service_id]
      rateable = Service.find(params[:service_id])
      target = service_ratings_path(rateable)
    elsif params[:provider_id]
      rateable = Provider.find(params[:provider_id])
      target = provider_ratings_path(rateable)
    end

    @ratings_proxy = RatingsProxy.new(rateable)

    respond_to do |format|
      format.js { render partial: 'ratings/form', locals: {url: target} }
    end
  end

  def create
    rating_params = params[:ratings]
    rating_params.keys.each do |k|
      rateable_params = rating_params[k]
      rateable = k.constantize.find(rateable_params[:id])
      r = rateable.rate(current_user, rateable_params[:value], rateable_params[:comments]) if rateable_params[:value]
      flash[:notice] = t(:rating_submitted_for_approval) if r.valid? # only flash on creation
    end

    redirect_to :back
  end

end

