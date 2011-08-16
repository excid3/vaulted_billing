require 'spec_helper'

describe VaultedBilling::Gateways::Ipcommerce do
  let(:gateway) { VaultedBilling.gateway(:ipcommerce).new }

  it { should be_a VaultedBilling::Gateway }

  shared_examples_for 'a no-op' do |expected_return_class|
    it { should be_success }
    it { should be_a expected_return_class }

    it 'does not make a service request' do
      expect { subject }.
        to_not raise_error(WebMock::NetConnectNotAllowedError)
    end
  end

  context '#add_customer' do
    let(:customer) { Factory.build(:customer) }
    subject { gateway.add_customer(customer) }
    it_should_behave_like 'a no-op', VaultedBilling::Customer
  end

  context '#add_customer_credit_card' do
    let(:customer) { Factory.build(:customer) }
    let(:credit_card) { Factory.build(:credit_card) }
    subject { gateway.add_customer_credit_card(customer, credit_card) }
    it_should_behave_like 'a no-op', VaultedBilling::CreditCard
  end

  context '#remove_customer' do
    let(:customer) { gateway.add_customer(Factory.build(:customer)) }
    subject { gateway.remove_customer(customer) }
    it_should_behave_like 'a no-op', VaultedBilling::Customer
  end

  context '#remove_customer_credit_card' do
    let(:customer) { Factory.build(:customer) }
    let(:credit_card) { Factory.build(:credit_card) }
    subject { gateway.remove_customer_credit_card(customer, credit_card) }
    it_should_behave_like 'a no-op', VaultedBilling::CreditCard
  end

  context '#update_customer' do
    let(:customer) { gateway.add_customer(Factory.build(:customer)) }
    subject { gateway.update_customer(customer) }
    it_should_behave_like 'a no-op', VaultedBilling::Customer
  end

  context '#update_customer_credit_card' do
    let(:customer) { Factory.build(:customer) }
    let(:credit_card) { Factory.build(:credit_card) }
    subject { gateway.update_customer_credit_card(customer, credit_card) }
    it_should_behave_like 'a no-op', VaultedBilling::CreditCard
  end

  context '#authorize' do
    let(:customer) { gateway.add_customer Factory.build(:customer) }
    subject { gateway.authorize(customer, credit_card, 11.00, {
      merchant_profile_id: 'AutoTest_E4FB800001',
      workflow_id: 'E4FB800001',
      employee_id: '12345',
      order_id: '3232',
      card_type_id: '1'
    }) }

    context 'when successful' do
      let(:credit_card) { gateway.add_customer_credit_card customer, Factory.build(:ipcommerce_credit_card) }
      use_vcr_cassette 'ipcommerce/authorize/success', :record => :new_episodes
      
      it_should_behave_like 'a transaction request'
      it { should be_success }
      its(:id) { should_not be_nil }
      it "returns a 32 character id" do
        subject.id.length.should == 32
      end
      its(:masked_card_number) { should be_present }
      its(:authcode) { should_not be_nil }
      its(:message) { should == "APPROVED" }
      its(:code) { should == 1 }
    end

    context 'with a failure' do
      let(:credit_card) { gateway.add_customer_credit_card customer, Factory.build(:credit_card) }
      use_vcr_cassette 'ipcommerce/authorize/failure', :record => :new_episodes
      
      it_should_behave_like 'a transaction request'
      
      it { should_not be_success }
      its(:message) { should_not == "APPROVED" }
    end
  end
  
  context '#capture' do
    let(:amount) { 11.00 }
    let(:customer) { gateway.add_customer Factory.build(:customer) }
    let(:credit_card) { gateway.add_customer_credit_card customer, Factory.build(:ipcommerce_credit_card) }
    let(:authorization) { gateway.authorize(customer, credit_card, 11.00, {
      merchant_profile_id: 'AutoTest_E4FB800001',
      workflow_id: 'E4FB800001',
      employee_id: '12345',
      order_id: '3232',
      card_type_id: '1'
    }) }

    context 'when successful' do
      subject { gateway.capture(authorization.id, amount, { workflow_id: 'E4FB800001' })}
      use_vcr_cassette 'ipcommerce/capture/success', :record => :new_episodes
      
      it_should_behave_like 'a transaction request'
      it { should be_success }
      its(:id) { should_not be_nil }
      it "returns a 32 character id" do
        subject.id.length.should == 32
      end
      its(:authcode) { should be_nil }
      its(:message) { should == "APPROVED" }
      its(:code) { should == 1 }
    end

    context 'with an invalid request' do
      subject { gateway.capture(authorization.id + "t", amount, { workflow_id: 'E4FB800001' })}
      use_vcr_cassette 'ipcommerce/capture/invalid', :record => :new_episodes
      
      it 'returns a Transaction' do
        subject.should be_kind_of(VaultedBilling::Transaction)
      end
      
      it { should_not be_success }
      its(:message) { should_not == "APPROVED" }
    end
    
    context 'with a failure' do
      pending
    end
  end
  
  context '#purchase' do
    let(:customer) { gateway.add_customer Factory.build(:customer) }
    subject { gateway.purchase(customer, credit_card, 10.00, {
      merchant_profile_id: 'AutoTest_E4FB800001',
      workflow_id: 'E4FB800001',
      employee_id: '12345',
      order_id: '3232',
      card_type_id: '1'
    }) }
    
    context 'when successful' do
      let(:credit_card) { gateway.add_customer_credit_card customer, Factory.build(:ipcommerce_credit_card) }
      use_vcr_cassette 'ipcommerce/purchase/success', :record => :new_episodes
      
      it_should_behave_like 'a transaction request'
      it { should be_success }
      its(:id) { should_not be_nil }
      it "returns a 32 character id" do
        subject.id.length.should == 32
      end
      its(:authcode) { should_not be_nil }
      its(:message) { should == "APPROVED" }
      its(:code) { should == 1 }
    end
    
    context 'with a failure' do
      let(:credit_card) { gateway.add_customer_credit_card customer, Factory.build(:credit_card) }
      use_vcr_cassette 'ipcommerce/purchase/failure', :record => :new_episodes
      
      it_should_behave_like 'a transaction request'
      
      it { should_not be_success }
      its(:message) { should_not == "APPROVED" }
    end
  end
  
  # Returning funds from a captured transaction
  context '#refund' do
    let(:customer) { gateway.add_customer(Factory.build(:customer)) }
    let(:credit_card) { gateway.add_customer_credit_card(customer, Factory.build(:ipcommerce_credit_card)) }
    let(:purchase) { gateway.purchase(customer, credit_card, 5.00, {
      merchant_profile_id: 'AutoTest_E4FB800001',
      workflow_id: 'E4FB800001',
      employee_id: '12345',
      order_id: '3232',
      card_type_id: '1'
    }) }

    subject { gateway.refund(purchase.id, 5.00, { workflow_id: 'E4FB800001' }) }
    
    context 'with a successful result' do
      use_vcr_cassette 'ipcommerce/refund/success', :record => :new_episodes
      
      it_should_behave_like 'a transaction request'
      it { should be_success }
      its(:id) { should_not be_nil }
      it "returns a 32 character id" do
        subject.id.length.should == 32
      end
      its(:authcode) { should_not be_nil }
      its(:message) { should == "APPROVED" }
      its(:code) { should == 1 }
    end
  end

  # Releasing funds from an authorized but uncaptured transaction
  context '#void' do
    let(:customer) { gateway.add_customer(Factory.build(:customer)) }
    let(:credit_card) { gateway.add_customer_credit_card(customer, Factory.build(:ipcommerce_credit_card)) }
    let(:authorization) { gateway.authorize(customer, credit_card, 5.00, {
      merchant_profile_id: 'AutoTest_E4FB800001',
      workflow_id: 'E4FB800001',
      employee_id: '12345',
      order_id: '3232',
      card_type_id: '1'
    }) }

    subject { gateway.void(authorization.id, { workflow_id: 'E4FB800001', merchant_profile_id: 'AutoTest_E4FB800001', :credit_card => credit_card, :card_type_id => 1  }) }

    context 'with a successful result', :focus => true do
      use_vcr_cassette 'ipcommerce/void/success', :record => :new_episodes
      
      it_should_behave_like 'a transaction request'
    end
    
    context 'with a failure' do
      use_vcr_cassette 'ipcommerce/void/failure', :record => :new_episodes
      pending
    end
  end
end
