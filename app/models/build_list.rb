# -*- encoding : utf-8 -*-
class BuildList < ActiveRecord::Base
  include Modules::Models::CommitAndVersion
  include Modules::Models::FileStoreClean
  include AbfWorker::ModelHelper

  belongs_to :project
  belongs_to :arch
  belongs_to :save_to_platform, :class_name => 'Platform'
  belongs_to :save_to_repository, :class_name => 'Repository'
  belongs_to :build_for_platform, :class_name => 'Platform'
  belongs_to :user
  belongs_to :advisory
  belongs_to :mass_build, :counter_cache => true
  has_many :items, :class_name => "BuildList::Item", :dependent => :destroy
  has_many :packages, :class_name => "BuildList::Package", :dependent => :destroy

  UPDATE_TYPES = %w[security bugfix enhancement recommended newpackage]
  RELEASE_UPDATE_TYPES = %w[security bugfix]

  validates :project_id, :project_version, :arch, :include_repos,
            :build_for_platform_id, :save_to_platform_id, :save_to_repository_id, :presence => true
  validates_numericality_of :priority, :greater_than_or_equal_to => 0
  validates :update_type, :inclusion => UPDATE_TYPES,
            :unless => Proc.new { |b| b.advisory.present? }
  validates :update_type, :inclusion => {:in => RELEASE_UPDATE_TYPES, :message => I18n.t('flash.build_list.frozen_platform')},
            :if => Proc.new { |b| b.advisory.present? }
  validate lambda {
    errors.add(:build_for_platform, I18n.t('flash.build_list.wrong_platform')) if save_to_platform.main? && save_to_platform_id != build_for_platform_id
  }
  validate lambda {
    errors.add(:build_for_platform, I18n.t('flash.build_list.wrong_build_for_platform')) unless build_for_platform.main?
  }
  validate lambda {
    errors.add(:save_to_repository, I18n.t('flash.build_list.wrong_repository')) unless save_to_repository_id.in? save_to_platform.repositories.map(&:id)
  }
  validate lambda {
    include_repos.each {|ir|
      errors.add(:save_to_repository, I18n.t('flash.build_list.wrong_include_repos')) unless build_for_platform.repository_ids.include? ir.to_i
    }
  }
  validate lambda {
    errors.add(:save_to_repository, I18n.t('flash.build_list.wrong_project')) unless save_to_repository.projects.exists?(project_id)
  }
  validate lambda {
    errors.add(:extra_repositories, I18n.t('flash.build_list.wrong_extra_repositories')) if extra_repositories.present? && Repository.where(:id => extra_repositories).count != extra_repositories.count
  }, :on => :create
  validate lambda {
    errors.add(:extra_containers, I18n.t('flash.build_list.wrong_extra_containers')) if extra_containers.present? && BuildList.where(:id => extra_containers, :container_status => BUILD_PUBLISHED).count != extra_containers.count
  }, :on => :create
  before_validation(:on => :create) do
    if save_to_repository && save_to_repository.platform.main?
      self.extra_repositories = nil
      self.extra_containers   = nil
    end
    self.extra_repositories = extra_repositories.uniq if extra_repositories.present?
    self.extra_containers   = extra_containers.uniq   if extra_containers.present?
  end

  before_create :use_save_to_repository_for_main_platforms

  attr_accessible :include_repos, :auto_publish, :build_for_platform_id, :commit_hash,
                  :arch_id, :project_id, :save_to_repository_id, :update_type,
                  :save_to_platform_id, :project_version, :use_save_to_repository,
                  :auto_create_container, :extra_repositories, :extra_containers
  LIVE_TIME = 4.week # for unpublished
  MAX_LIVE_TIME = 3.month # for published

  SUCCESS = 0
  ERROR   = 1

  PROJECT_VERSION_NOT_FOUND = 4
  PROJECT_SOURCE_ERROR      = 6
  DEPENDENCIES_ERROR        = 555
  BUILD_ERROR               = 666
  BUILD_STARTED             = 3000
  BUILD_CANCELED            = 5000
  WAITING_FOR_RESPONSE      = 4000
  BUILD_PENDING             = 2000
  BUILD_PUBLISHED           = 6000
  BUILD_PUBLISH             = 7000
  FAILED_PUBLISH            = 8000
  REJECTED_PUBLISH          = 9000
  BUILD_CANCELING           = 10000
  TESTS_FAILED              = 11000

  STATUSES = [  WAITING_FOR_RESPONSE,
                BUILD_CANCELED,
                BUILD_PENDING,
                BUILD_PUBLISHED,
                BUILD_CANCELING,
                BUILD_PUBLISH,
                FAILED_PUBLISH,
                REJECTED_PUBLISH,
                SUCCESS,
                BUILD_STARTED,
                BUILD_ERROR,
                PROJECT_VERSION_NOT_FOUND,
                TESTS_FAILED
              ]

  HUMAN_STATUSES = { WAITING_FOR_RESPONSE => :waiting_for_response,
                     BUILD_CANCELED => :build_canceled,
                     BUILD_CANCELING => :build_canceling,
                     BUILD_PENDING => :build_pending,
                     BUILD_PUBLISHED => :build_published,
                     BUILD_PUBLISH => :build_publish,
                     FAILED_PUBLISH => :failed_publish,
                     REJECTED_PUBLISH => :rejected_publish,
                     BUILD_ERROR => :build_error,
                     BUILD_STARTED => :build_started,
                     SUCCESS => :success,
                     PROJECT_VERSION_NOT_FOUND => :project_version_not_found,
                     TESTS_FAILED => :tests_failed
                    }

  scope :recent, order("#{table_name}.updated_at DESC")
  scope :for_status, lambda {|status| where(:status => status) }
  scope :for_user, lambda { |user| where(:user_id => user.id)  }
  scope :for_platform, lambda { |platform| where(:build_for_platform_id => platform)  }
  scope :by_mass_build, lambda { |mass_build| where(:mass_build_id => mass_build)  }
  scope :scoped_to_arch, lambda {|arch| where(:arch_id => arch) }
  scope :scoped_to_save_platform, lambda {|pl_id| where(:save_to_platform_id => pl_id) }
  scope :scoped_to_project_version, lambda {|project_version| where(:project_version => project_version) }
  scope :scoped_to_is_circle, lambda {|is_circle| where(:is_circle => is_circle) }
  scope :for_creation_date_period, lambda{|start_date, end_date|
    s = scoped
    s = s.where(["build_lists.created_at >= ?", start_date]) if start_date
    s = s.where(["build_lists.created_at <= ?", end_date]) if end_date
    s
  }
  scope :for_notified_date_period, lambda{|start_date, end_date|
    s = scoped
    s = s.where(["build_lists.updated_at >= ?", start_date]) if start_date
    s = s.where(["build_lists.updated_at <= ?", end_date]) if end_date
    s
  }
  scope :scoped_to_project_name, lambda {|project_name| joins(:project).where('projects.name LIKE ?', "%#{project_name}%")}
  scope :scoped_to_new_core, lambda {|new_core| where(:new_core => new_core)}
  scope :outdated, where('created_at < ? AND status <> ? OR created_at < ?', Time.now - LIVE_TIME, BUILD_PUBLISHED, Time.now - MAX_LIVE_TIME)

  serialize :additional_repos
  serialize :include_repos
  serialize :results, Array
  serialize :extra_repositories, Array
  serialize :extra_containers, Array

  after_commit  :place_build
  after_destroy :remove_container

  state_machine :status, :initial => :waiting_for_response do

    # WTF? around_transition -> infinite loop
    before_transition do |build_list, transition|
      status = HUMAN_STATUSES[build_list.status]
      if build_list.mass_build && MassBuild::COUNT_STATUSES.include?(status)
        MassBuild.decrement_counter "#{status.to_s}_count", build_list.mass_build_id
      end
    end

    after_transition do |build_list, transition|
      status = HUMAN_STATUSES[build_list.status]
      if build_list.mass_build && MassBuild::COUNT_STATUSES.include?(status)
        MassBuild.increment_counter "#{status.to_s}_count", build_list.mass_build_id
      end
    end

    after_transition :on => :published,
      :do => [:set_version_and_tag, :actualize_packages]
    after_transition :on => :cancel, :do => :cancel_job

    after_transition :on => [:published, :fail_publish, :build_error, :tests_failed], :do => :notify_users
    after_transition :on => :build_success, :do => :notify_users,
      :unless => lambda { |build_list| build_list.auto_publish? }

    event :place_build do
      transition :waiting_for_response => :build_pending, :if => lambda { |build_list|
        build_list.add_to_queue == BuildList::SUCCESS
      }
      %w[BUILD_PENDING PROJECT_VERSION_NOT_FOUND].each do |code|
        transition :waiting_for_response => code.downcase.to_sym, :if => lambda { |build_list|
          build_list.add_to_queue == BuildList.const_get(code)
        }
      end
    end

    event :start_build do
      transition [ :build_pending, :project_version_not_found ] => :build_started
    end

    event :cancel do
      transition [:build_pending, :build_started] => :build_canceling
    end

    # :build_canceling => :build_canceled - canceling from UI
    # :build_started => :build_canceled - canceling from worker by time-out (time_living has been expired)
    event :build_canceled do
      transition [:build_canceling, :build_started] => :build_canceled
    end

    event :published do
      transition [:build_publish, :rejected_publish] => :build_published
    end

    event :fail_publish do
      transition [:build_publish, :rejected_publish] => :failed_publish
    end

    event :publish do
      transition [:success, :failed_publish, :build_published, :tests_failed] => :build_publish
      transition [:success, :failed_publish] => :failed_publish
    end

    event :reject_publish do
      transition [:success, :failed_publish, :tests_failed] => :rejected_publish, :if => :can_reject_publish?
    end

    event :build_success do
      transition [:build_started, :build_canceled] => :success
    end

    [:build_error, :tests_failed].each do |kind|
      event kind do
        transition [:build_started, :build_canceling] => kind
      end
    end

    HUMAN_STATUSES.each do |code,name|
      state name, :value => code
    end
  end

  later :publish, :queue => :clone_build


  HUMAN_CONTAINER_STATUSES = { WAITING_FOR_RESPONSE => :waiting_for_publish,
                               BUILD_PUBLISHED => :container_published,
                               BUILD_PUBLISH => :container_publish,
                               FAILED_PUBLISH => :container_failed_publish
                              }

  state_machine :container_status, :initial => :waiting_for_publish do

    after_transition :on => :publish_container, :do => :create_container
    after_transition :on => [:fail_publish_container, :destroy_container],
      :do => :remove_container

    event :publish_container do
      transition [:waiting_for_publish, :container_failed_publish] => :container_publish,
        :if => :can_create_container?
    end

    event :published_container do
      transition :container_publish => :container_published
    end

    event :fail_publish_container do
      transition :container_publish => :container_failed_publish
    end

    event :destroy_container do
      transition [:container_failed_publish, :container_published, :waiting_for_publish] => :waiting_for_publish
    end

    HUMAN_CONTAINER_STATUSES.each do |code,name|
      state name, :value => code
    end
  end

  def set_version_and_tag
    pkg = self.packages.where(:package_type => 'source', :project_id => self.project_id).first
    # TODO: remove 'return' after deployment ABF kernel 2.0
    return if pkg.nil? # For old client that does not sends data about packages
    self.package_version = "#{pkg.platform.name}-#{pkg.version}-#{pkg.release}"
    system("cd #{self.project.repo.path} && git tag #{self.package_version} #{self.commit_hash}") # TODO REDO through grit
    save
  end

  def actualize_packages
    ActiveRecord::Base.transaction do
      # packages from previous build_list
      self.last_published.limit(2).last.packages.update_all :actual => false
      self.packages.update_all :actual => true
    end
  end

  def can_create_container?
    (can_publish? || build_publish?) && [WAITING_FOR_RESPONSE, FAILED_PUBLISH].include?(container_status)
  end

  #TODO: Share this checking on product owner.
  def can_cancel?
    build_started? || build_pending?
  end

  def can_publish?
    [SUCCESS, FAILED_PUBLISH, BUILD_PUBLISHED, TESTS_FAILED].include? status
  end

  def can_reject_publish?
    can_publish? && !save_to_repository.publish_without_qa && !build_published?
  end

  def add_to_queue
    # TODO: Investigate: why 2 tasks will be created without checking @state
    unless @status
      add_job_to_abf_worker_queue
      update_column(:bs_id, id)
    end
    @status ||= BUILD_PENDING
  end

  def self.human_status(status)
    I18n.t("layout.build_lists.statuses.#{HUMAN_STATUSES[status]}")
  end

  def human_status
    self.class.human_status(status)
  end

  def self.status_by_human(human)
    HUMAN_STATUSES.key human
  end

  def set_items(items_hash)
    self.items = []

    items_hash.each do |level, items|
      items.each do |item|
        self.items << self.items.build(:name => item['name'], :version => item['version'], :level => level.to_i)
      end
    end
  end

  def set_packages(pkg_hash, project_name)
    prj = Project.joins(:repositories => :platform).where('platforms.id = ?', save_to_platform.id).find_by_name!(project_name)
    build_package(pkg_hash['srpm'], 'source', prj) {|p| p.save!}
    pkg_hash['rpm'].each do |rpm_hash|
      build_package(rpm_hash, 'binary', prj) {|p| p.save!}
    end
  end

  def event_log_message
    {:project => project.name, :version => project_version, :arch => arch.name}.inspect
  end

  def current_duration
    (Time.now.utc - started_at.utc).to_i
  end

  def human_current_duration
    I18n.t("layout.build_lists.human_current_duration", {:hours => (current_duration/3600).to_i, :minutes => (current_duration%3600/60).to_i})
  end

  def human_duration
    I18n.t("layout.build_lists.human_duration", {:hours => (duration/3600).to_i, :minutes => (duration%3600/60).to_i})
  end

  def in_work?
    status == BUILD_STARTED
    #[WAITING_FOR_RESPONSE, BUILD_PENDING, BUILD_STARTED].include?(status)
  end

  def associate_and_create_advisory(params)
    build_advisory(params){ |a| a.update_type = update_type }
    advisory.attach_build_list(self)
  end

  def can_attach_to_advisory?
    !save_to_repository.publish_without_qa &&
      save_to_platform.main? &&
      save_to_platform.released &&
      build_published?
  end

  def log(load_lines)
    new_core? ? abf_worker_log : I18n.t('layout.build_lists.log.not_available')
  end

  def last_published
    BuildList.where(:project_id => self.project_id,
                    :save_to_repository_id => self.save_to_repository_id)
             .for_platform(self.build_for_platform_id)
             .scoped_to_arch(self.arch_id)
             .for_status(BUILD_PUBLISHED)
             .recent
  end

  def sha1_of_file_store_files
    packages.pluck(:sha1).compact | (results || []).map{ |r| r['sha1'] }.compact
  end

  protected

  def create_container
    AbfWorker::BuildListsPublishTaskManager.create_container_for self
  end

  def remove_container
    system "rm -rf #{save_to_platform.path}/container/#{id}" if save_to_platform
  end

  def abf_worker_priority
    mass_build_id ? '' : 'default'
  end

  def abf_worker_base_queue
    'rpm_worker'
  end

  def abf_worker_args
    # TODO: remove when this will be not necessary
    # "rosa2012.1/main" repository should be used in "conectiva" platform
    repos = include_repos
    repos |= ['146'] if build_for_platform_id == 376
    include_repos_hash = {}.tap do |h|
      repos.each do |r|
        repo = Repository.find r
        path = repo.platform.public_downloads_url(nil, arch.name, repo.name)
        # path.gsub!(/^http:\/\/(0\.0\.0\.0|localhost)\:[\d]+/, 'https://abf.rosalinux.ru') unless Rails.env.production?
        # Path looks like:
        # http://abf.rosalinux.ru/downloads/rosa-server2012/repository/x86_64/base/
        # so, we should append:
        # - release
        # - updates
        h["#{repo.platform.name}_#{repo.name}_release"] = path + 'release'
        h["#{repo.platform.name}_#{repo.name}_updates"] = path + 'updates'
      end
    end
    if save_to_platform.personal? && use_save_to_repository
      include_repos_hash["#{save_to_platform.name}_release"] = save_to_platform.
        urpmi_list(nil, nil, false, save_to_repository.name)["#{build_for_platform.name}"]["#{arch.name}"]
    end

    git_project_address = project.git_project_address(user)
    # git_project_address.gsub!(/^http:\/\/(0\.0\.0\.0|localhost)\:[\d]+/, 'https://abf.rosalinux.ru') unless Rails.env.production?
    {
      :id                   => id,
      :arch                 => arch.name,
      :time_living          => 43200, # 12 hours
      :distrib_type         => build_for_platform.distrib_type,
      :git_project_address  => git_project_address,
      :commit_hash          => commit_hash,
      :include_repos        => include_repos_hash,
      :bplname              => build_for_platform.name,
      :user                 => {:uname => user.uname, :email => user.email}
    }
  end

  def notify_users
    unless mass_build_id
      users = []
      if project # find associated users
        users = project.all_members.
          select{ |user| user.notifier.can_notify? && user.notifier.new_associated_build? }
      end
      if user.notifier.can_notify? && user.notifier.new_build?
        users = users | [user]
      end
      users.each do |user|
        UserMailer.build_list_notification(self, user).deliver
      end
    end
  end # notify_users

  def build_package(pkg_hash, package_type, prj)
    packages.create(pkg_hash) do |p|
      p.project = prj
      p.platform = save_to_platform
      p.package_type = package_type
      yield p
    end
  end

  def use_save_to_repository_for_main_platforms
    self.use_save_to_repository = true if save_to_platform.main?
  end
end
