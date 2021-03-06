require 'spec_helper'

shared_examples_for 'product build list admin' do

  it "should be able to perform create action" do
    expect {
      post :create, valid_attributes
    }.to change(ProductBuildList, :count).by(1)
    expect(response).to redirect_to([@product.platform, @product])
  end

  it "should be able to perform destroy action" do
    @pbl.update_column(:project_id, nil)
    expect {
      delete :destroy, valid_attributes_for_destroy
    }.to change(ProductBuildList, :count).by(-1)
    expect(response).to redirect_to([@pbl.product.platform, @pbl.product])
  end

  it 'should be able to perform index action' do
    get :index
    expect(response).to render_template(:index)
  end

  it 'should be able to perform cancel action' do
    url = platform_product_product_build_list_path(@product.platform, @product, @pbl)
    @request.env['HTTP_REFERER'] = url
    put :cancel, valid_attributes_for_show
    expect(response).to redirect_to(url)
  end

  it 'should be able to perform show action' do
    get :show, valid_attributes_for_show
    expect(response).to render_template(:show)
  end

  it 'should be able to perform update action' do
    put :update, valid_attributes_for_show.merge(product_build_list: {time_living: 100,not_delete: true})
    expect(response).to be_success
  end

  it "ensures that only not_delete field of product build list has been updated" do
    put :update, valid_attributes_for_show.merge(product_build_list: {time_living: 100,not_delete: true})
    time_living = @pbl.time_living
    expect(@pbl.reload.time_living).to eq time_living
    expect(@pbl.not_delete).to be_truthy
  end

  it 'should be able to perform log action' do
    get :log, valid_attributes_for_show
    expect(response).to be_success
  end

end

shared_examples_for 'product build list user without admin rights' do
  it 'should not be able to perform create action' do
    expect {
      post :create, valid_attributes
    }.to_not change(ProductBuildList, :count)
    expect(response).to_not be_success
  end

  it 'should not be able to perform destroy action' do
    @pbl.update_column(:project_id, nil)
    expect {
      delete :destroy, valid_attributes_for_destroy
    }.to change(ProductBuildList, :count).by(0)
    expect(response).to_not be_success
  end

  it 'should not be able to perform cancel action' do
    put :cancel, valid_attributes_for_show
    expect(response).to_not redirect_to(platform_product_product_build_list_path(@product.platform, @product, @pbl))
  end

  it 'should not be able to perform update action' do
    put :update, valid_attributes_for_show
    expect(response).to_not be_success
  end

end

shared_examples_for 'product build list user' do
  it 'should be able to perform index action' do
    get :index
    expect(response).to render_template(:index)
  end

  it 'should be able to perform show action' do
    get :show, valid_attributes_for_show
    expect(response).to render_template(:show)
  end

  it 'should be able to perform log action' do
    get :log, valid_attributes_for_show
    expect(response).to be_success
  end
end

describe Platforms::ProductBuildListsController, type: :controller do
  before(:each) { stub_symlink_methods }

  context 'crud' do

    before do
      FactoryGirl.create(:arch, name: 'x86_64')
      @arch = FactoryGirl.create(:arch)
      @product = FactoryGirl.create(:product)
      @pbl = FactoryGirl.create(:product_build_list, product: @product)
    end

    def valid_attributes
      {product_id: @product.id, platform_id: @product.platform_id, product_build_list: {main_script: 'build.sh', time_living: 60, project_version: 'master', arch_id: @arch.id}}
    end

    def valid_attributes_for_destroy
      {id: @pbl.id, product_id: @pbl.product.id, platform_id: @pbl.product.platform.id }
    end

    def valid_attributes_for_show
      valid_attributes_for_destroy
    end

    context 'for guest' do
      it_should_behave_like 'product build list user without admin rights'

      if APP_CONFIG['anonymous_access']
        it_should_behave_like 'product build list user'
      else
        [:index, :show, :log].each do |action|
          it "should not be able to perform #{action}" do
            get action, valid_attributes_for_show
            expect(response).to redirect_to(new_user_session_path)
          end
        end
      end
    end

    context 'for user' do
      before(:each) { set_session_for FactoryGirl.create(:user) }

      it_should_behave_like 'product build list user'
      it_should_behave_like 'product build list user without admin rights'

    end

    context 'for platform admin' do
      before(:each) do
        @user = FactoryGirl.create(:user)
        set_session_for(@user)
        create_relation(@product.platform, @user, 'admin')
      end

      it_should_behave_like 'product build list admin'
      it_should_behave_like 'product build list user'
    end

    context 'for global admin' do
      before(:each)  {  set_session_for FactoryGirl.create(:admin) }

      it_should_behave_like 'product build list admin'
      it_should_behave_like 'product build list user'

    end
  end

end
