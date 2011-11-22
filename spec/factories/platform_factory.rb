Factory.define(:platform) do |p|
  p.name { Factory.next(:string) }
  p.unixname { Factory.next(:unixname) }
  p.platform_type 'main'
  p.distrib_type APP_CONFIG['distr_types'].first
  p.association :owner, :factory => :user
end