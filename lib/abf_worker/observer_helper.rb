module AbfWorker
  module ObserverHelper
    BUILD_COMPLETED = 0
    BUILD_FAILED    = 1
    BUILD_PENDING   = 2
    BUILD_STARTED   = 3
    BUILD_CANCELED  = 4

    def update_results(subject, options)
      results = (subject.results || [])+ options['results']
      subject.results = results.sort_by{ |r| r['file_name'] }
      subject.save!
    end

  end
end