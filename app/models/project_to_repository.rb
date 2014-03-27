class ProjectToRepository < ActiveRecord::Base
  AUTOSTART_OPTIONS = %w(auto_publish user_id enabled)

  belongs_to :project
  belongs_to :repository

  delegate :path, to: :project

  scope :autostart_enabled, -> { where("autostart_options -> 'enabled' = 'true'") }

  after_destroy -> { project.destroy_project_from_repository(repository) }, unless: -> { Thread.current[:skip] }

  validate :one_project_in_platform_repositories, on: :create

  attr_accessible :project, :project_id

  AUTOSTART_OPTIONS.each do |field|
    store_accessor :autostart_options, field
  end

  def enabled?
    ['true', true].include?(enabled)
  end

  def auto_publish?
    ['true', true].include?(auto_publish)
  end

  protected

  def one_project_in_platform_repositories
    if Project.joins(repositories: :platform).where('platforms.id = ?', repository.platform_id).by_name(project.name).exists?
      errors.add(:base, I18n.t('activerecord.errors.project_to_repository.project'))
    end
  end
end
