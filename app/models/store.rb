class Store < ActiveRecord::Base

  include ActiveRecord::Archive

  belongs_to :crawl

  attr_writer :latitude, :longitude

  archive :crawl_id, [
    :is_hidden,
    :products_count,
    :inventory_count,
    :inventory_price_in_cents,
    :inventory_volume_in_milliliters
  ].concat(
    Date::DAYNAMES.map do |day|
      [:"#{day.downcase}_open", :"#{day.downcase}_close"]
    end.flatten
  )

  before_validation :set_geo

  def self.place(attrs)
    id = attrs[:store_id] || attrs[:store_no] || attrs[:id]
    if (store = where(:id => id).first)
      store.update_attributes(attrs)
    else
      create(attrs)
    end
  end

  def store_no=(value)
    self.id = value
  end

  def store_no
    id
  end

  def latitude
    geo.x
  end

  def longitude
    geo.y
  end

  def as_json
    { :store_no => store_no,
      :latitude => latitude,
      :longitude => longitude }.
      merge(super).
      exclude(:id, :is_hidden)
  end

  protected

  def set_geo
    self.geo = Point.from_x_y(@latitude, @longitude, 4326)
  end

end

