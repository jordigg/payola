module Payola
  class ChargeCard
    def self.call(sale)
      sale.save!
      secret_key = Payola.secret_key_for_sale(sale)

      begin
        sale.verify_charge!

        if sale.state == "authorizing"
          customer = create_customer(sale, secret_key)
          charge = capture_payment(sale, secret_key)
          update_sale(sale, customer, charge, secret_key)
        else
          customer = create_customer(sale, secret_key)
          charge = create_charge(sale, customer, secret_key)
          update_sale(sale, customer, charge, secret_key)
        end

      rescue Stripe::StripeError, RuntimeError => e
        sale.update_attributes(error: e.message)
        sale.fail!
      end

      sale
    end

    def self.create_customer(sale, secret_key)
      if sale.stripe_customer_id.present?
        Stripe::Customer.retrieve(sale.stripe_customer_id, secret_key)
      else
        if Payola::Sale.where(:email => sale.email).where.not(:stripe_customer_id => nil).any?
          stripe_customer_id = Payola::Sale.where(:email => sale.email).where.not(:stripe_customer_id => nil).first.stripe_customer_id
        end
        if stripe_customer_id.present?
          Stripe::Customer.retrieve(stripe_customer_id, secret_key)
        else
          Stripe::Customer.create({
            source: sale.stripe_token,
            email: sale.email
          }, secret_key)
        end
      end
    end

    def self.create_charge(sale, customer, secret_key)
      capture = sale.product.has_attribute?(:capture_payment) ? sale.product.capture_payment : true
      charge_attributes = {
        amount: sale.amount,
        currency: sale.currency,
        customer: customer.id,
        description: sale.guid,
        capture: capture,
      }.merge(Payola.additional_charge_attributes.call(sale, customer))

      Stripe::Charge.create(charge_attributes, secret_key)
    end

    def self.update_sale(sale, customer, charge, secret_key)
      if charge.respond_to?(:captured) && charge.captured == false
        sale.update_attributes(
          stripe_id:          charge.id,
          stripe_customer_id: customer.id,
          card_last4:         charge.source.last4,
          card_expiration:    Date.new(charge.source.exp_year, charge.source.exp_month, 1),
          card_type:          charge.source.brand
        )

        sale.authorize!
      else
        if charge.respond_to?(:fee)
          fee = charge.fee
        else
          balance = Stripe::BalanceTransaction.retrieve(charge.balance_transaction, secret_key)
          fee = balance.fee
        end

        sale.update_attributes(
          stripe_id:          charge.id,
          stripe_customer_id: customer.id,
          card_last4:         charge.source.last4,
          card_expiration:    Date.new(charge.source.exp_year, charge.source.exp_month, 1),
          card_type:          charge.source.brand,
          fee_amount:         fee
        )

        sale.finish!
      end
    end

    def self.capture_payment(sale, secret_key)
      charge = Stripe::Charge.retrieve(sale.stripe_id, secret_key)
      if charge.amount != sale.product.price
        charge.capture({amount: sale.product.price})
      else
        charge.capture
      end
    end

  end
end
