# -*- encoding : utf-8 -*-
class SettingsNotifier < ActiveRecord::Base
  belongs_to :user

  validates :user_id, :presence => true
end