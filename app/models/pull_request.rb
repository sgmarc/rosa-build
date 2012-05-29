class PullRequest < ActiveRecord::Base
  belongs_to :issue, :autosave => true, :dependent => :destroy, :touch => true, :validate => true
  belongs_to :base_project, :class_name => 'Project', :foreign_key => 'base_project_id'
  belongs_to :head_project, :class_name => 'Project', :foreign_key => 'head_project_id'
  delegate :user, :title, :body, :serial_id, :assignee, :status, :to => :issue, :allow_nil => true
  accepts_nested_attributes_for :issue
  #attr_accessible #FIXME disable for development
  validate :uniq_merge
  validates_each :head_ref, :base_ref do |record, attr, value|
    project = attr == :head_ref ? record.head_project : record.base_project
    if !((project.branches + project.tags).map(&:name).include?(value) || project.git_repository.commits.map(&:id).include?(value))
      record.errors.add attr, I18n.t('projects.pull_requests.wrong_ref')
    end
  end

  before_create :clean_dir
  after_destroy :clean_dir

  scope :needed_checking, includes(:issue).where(:issues => {:status => ['open', 'blocked', 'ready', 'already']})

  state_machine :status, :initial => :open do
    #after_transition [:ready, :blocked] => [:merged, :closed] do |pull, transition|
    #  FileUtils.rm_rf(pull.path) # What about diff?
    #end

    event :ready do
      transition [:ready, :open, :blocked] => :ready
    end

    event :block do
      transition [:blocked, :open, :ready] => :blocked
    end

    event :already do
      transition [:open, :blocked, :ready] => :already
    end

    event :merging do
      transition :ready => :merged
    end

    event :close do
      transition [:open, :ready, :blocked] => :closed
    end

    event :reopen do
      transition :closed => :open
    end
  end

  def status=(value)
    issue.status = value
  end

  def can_merge?
    status == 'ready'
  end

  def check
    ret = merge
    if ret =~ /Already up-to-date/
      already
    elsif ret =~ /Merge made by the 'recursive' strategy/
      system("cd #{path} && git reset --hard HEAD^") # remove merge commit
      ready
    elsif ret =~ /Automatic merge failed/
      system("cd #{path} && git reset --hard HEAD")
      block
    else
      raise ret
    end
  end

  def soft_check
    ret = merge
    if ret =~ /Already up-to-date/
      'already'
    elsif ret =~ /Merge made by the 'recursive' strategy/
      system("cd #{path} && git reset --hard HEAD^") # remove merge commit
      'ready'
    elsif ret =~ /Automatic merge failed/
      system("cd #{path} && git reset --hard HEAD")
      'block'
    else
      raise ret
    end
  end

  def merge!(who)
    return false unless can_merge?
    Dir.chdir(path) do
      system "git config user.name \"#{who.uname}\" && git config user.email \"#{who.email}\""
      if merge
        merging
        system("git push origin HEAD")
        system("git reset --hard HEAD") # for diff maybe FIXME
      end
    end
  end

  def self.default_base_project(project)
    project.is_root? ? project : project.root
  end


  def path
    filename = [id, base_ref, head_project.owner.uname, head_project.name, head_ref].compact.join('-')
    if Rails.env == "production"
      File.join('/srv/rosa_build/shared/tmp', "pull_requests", base_project.owner.uname, base_project.name, filename)
    else
      File.join(Rails.root, "tmp", Rails.env, "pull_requests", base_project.owner.uname, base_project.name, filename)
    end
  end

  def head_branch
    if base_project != head_project
      "head_#{head_ref}"
    else
      head_ref
    end
  end

  def diff_stats
    stats = []
    Dir.chdir(path) do
      lines = %x(git diff --numstat #{base_ref} #{head_ref}).split("\n")
      while !lines.empty?
        files = []
        while lines.first =~ /^([-\d]+)\s+([-\d]+)\s+(.+)/
          additions, deletions, filename = lines.shift.split
          additions, deletions = additions.to_i, deletions.to_i
          total = additions + deletions
          stat = Grit::DiffStat.new filename, additions, deletions, total
          stats << stat
        end
      end
      stats
    end
  end

  protected

  def merge
    clone
    %x(cd #{path} && git checkout #{base_ref} && git merge --no-ff #{head_branch}) #FIXME need sanitize branch name!
  end

  def clone
    git = Grit::Git.new(path)

    unless git.exist?
      FileUtils.mkdir_p(path)
      system("git clone --local --no-hardlinks #{base_project.path} #{path}")
      if base_project != head_project
        Dir.chdir(path) do
          system 'git', 'remote', 'add', 'head', head_project.path
        end
      end
    end

    clean
    Dir.chdir(path) do
      system 'git', 'checkout', base_ref
      system 'git', 'pull',  'origin', base_ref
      if base_project == head_project
        system 'git', 'checkout', head_ref
        system 'git', 'pull', 'origin', head_ref
      else
        system 'git', 'fetch', 'head', "+#{head_ref}:#{head_branch}"
      end
    end
    # TODO catch errors
  end

  def clean
    Dir.chdir(path) do
      base_project.branches.each {|branch| system 'git', 'checkout', branch.name}
      system 'git', 'checkout', base_ref

      base_project.branches.each do |branch|
        system 'git', 'branch', '-D', branch.name unless [base_ref, head_branch].include? branch.name
      end
      base_project.tags.each do |tag|
        system 'git', 'tag', '-d', tag.name unless [base_ref, head_branch].include? tag.name
      end
    end
  end

  def uniq_merge
    if base_project.pull_requests.needed_checking.where(:head_project_id => head_project, :base_ref => base_ref, :head_ref => head_ref).where('pull_requests.id <> :id or :id is null', :id => id).count > 0
      errors.add(:base_branch, I18n.t('projects.pull_requests.duplicate', :head_ref => head_ref))
    end
  end

  def clean_dir
    FileUtils.rm_rf path
  end
end
