module Payola
  class CaptureSale
    def self.call(guid)
      Sale.find_by(guid: guid).capture!
    end
  end
end
