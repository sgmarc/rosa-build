class Advisory < ActiveRecord::Base
  has_and_belongs_to_many :platforms
  has_and_belongs_to_many :projects
  has_many :build_lists

  validates :description, :update_type, :presence => true
  validates :update_type, :inclusion => BuildList::RELEASE_UPDATE_TYPES

  after_create :generate_advisory_id
  before_save  :normalize_references, :if => :references_changed?

  ID_TEMPLATE        = 'ROSA-%<type>s-%<year>d:%<id>04d'
  ID_STRING_TEMPLATE = 'ROSA-%<type>s-%<year>04s:%<id>04s'
  TYPES = {'security' => 'SA', 'bugfix' => 'A'}

  scope :search_by_id, lambda { |aid| where('advisory_id ILIKE ?', "%#{aid.to_s.strip}%") }
  scope :by_update_type, lambda { |ut| where(:update_type => ut) }
  default_scope order('created_at DESC')

  def to_param
    advisory_id
  end

  def attach_build_list(build_list)
    return false if update_type != build_list.update_type
    self.platforms  << build_list.save_to_platform unless platforms.include? build_list.save_to_platform
    self.projects   << build_list.project unless projects.include? build_list.project
    build_list.advisory = self
    save
  end

  # this method fetches and structurize packages attached to current advisory.
  def fetch_packages_info
    packages_info = Hash.new { |h, k| h[k] = {} } # maaagic, it's maaagic ;)
    build_lists.find_in_batches(:include => [:save_to_platform, :packages, :project]) do |batch|
      batch.each do |build_list|
        tmp = build_list.packages.inject({:srpm => nil, :rpm => []}) do |h, p|
          p.package_type == 'binary' ? h[:rpm] << p.fullname : h[:srpm] = p.fullname
          h
        end
        h = { build_list.project => tmp }
        packages_info[build_list.save_to_platform].merge!(h) do |pr, old, new|
          {:srpm => new[:srpm], :rpm => old[:rpm].concat(new[:rpm]).uniq}
        end
      end
    end
    packages_info
  end

  protected

  def generate_advisory_id
    self.advisory_id = sprintf(ID_TEMPLATE, :type => TYPES[self.update_type], :year => Time.now.utc.year, :id => self.id)
    self.save
  end

  def normalize_references
    self.references.gsub!(/\r| /, '')
    self.references = self.references.split('\n').map do |ref|
      ref = CGI::escapeHTML(ref)
      ref = "http://#{ref}" unless ref =~ %r[^http(s?)://*]
      ref
    end.join("\n")
  end

end
Advisory.include_root_in_json = false