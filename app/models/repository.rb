class Repository < ActiveRecord::Base
  belongs_to :platform
  belongs_to :owner, :polymorphic => true

  has_many :projects, :through => :project_to_repositories #, :dependent => :destroy
  has_many :project_to_repositories, :validate => true, :dependent => :destroy

  has_many :relations, :as => :target, :dependent => :destroy
  has_many :objects, :as => :target, :class_name => 'Relation', :dependent => :destroy
  has_many :members, :through => :objects, :source => :object, :source_type => 'User'
  has_many :groups,  :through => :objects, :source => :object, :source_type => 'Group'

  validates :name, :uniqueness => {:scope => :platform_id}, :presence => true
  validates :unixname, :uniqueness => {:scope => :platform_id}, :presence => true, :format => { :with => /^[a-z0-9_]+$/ }
  # validates :platform_id, :presence => true # if you uncomment this platform clone will not work

  scope :recent, order("name ASC")

  after_create :make_owner_rel
  before_save :check_owner_rel
  #before_save :create_directory
  #after_destroy :remove_directory

  before_create :xml_rpc_create, :unless => lambda {Thread.current[:skip]}
  before_destroy :xml_rpc_destroy

  attr_accessible :name, :unixname, :platform_id
  
#  def path
#    build_path(unixname)
#  end

  def full_clone(attrs) # owner
    clone.tap do |c| # dup
      c.attributes = attrs
      c.updated_at = nil; c.created_at = nil # :id = nil
      c.projects = projects
    end
  end

  protected

#   def build_path(dir)
#     File.join(platform.path, dir)
#   end
#
#   def create_directory
#     exists = File.exists?(path) && File.directory?(path)
#     raise "Directory #{path} already exists" if exists
#     if new_record?
#       FileUtils.mkdir_p(path)
#       %w(release updates).each { |subrep| FileUtils.mkdir_p(path + subrep) }
#     elsif unixname_changed?
#       FileUtils.mv(build_path(unixname_was), buildpath(unixname))
#     end 
#   end
#
#   def remove_directory
#     exists = File.exists?(path) && File.directory?(path)
#     raise "Directory #{path} didn't exists" unless exists
#     FileUtils.rm_rf(path)
#   end

    def xml_rpc_create
      result = BuildServer.create_repo unixname, platform.unixname
      if result == BuildServer::SUCCESS
        return true
      else
        raise "Failed to create repository #{name} inside platform #{platform.name} with code #{result}."
      end      
    end

    def xml_rpc_destroy
      result = BuildServer.delete_repo unixname, platform.unixname
      if result == BuildServer::SUCCESS
        return true
      else
        raise "Failed to delete repository #{name} inside platform #{platform.name}."
      end
    end

    def make_owner_rel
      r = relations.build :object_id => owner.id, :object_type => 'User', :role => 'admin'
      r.save
    end

    def check_owner_rel
      if !new_record? and owner_id_changed?
        relations.by_object(owner).delete_all if owner_type_was
        make_owner_rel if owner
      end
    end

end
