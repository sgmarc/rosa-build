
require "spec_helper"

describe Projects::ProjectsController do
  describe "routing" do

    it "routes to #index" do
      get("/projects").should route_to("projects/projects#index")
    end

    it "routes to #new" do
      get("/projects/new").should route_to("projects/projects#new")
    end

    it "routes to #edit" do
      get("/import/glib2.0-mib/modify").should route_to("projects/projects#edit", name_with_owner: 'import/glib2.0-mib')
    end

    it "routes to #create" do
      post("/projects").should route_to("projects/projects#create")
    end

    it "routes to #destroy" do
      delete("/import/glib2.0-mib").should route_to("projects/projects#destroy", name_with_owner: 'import/glib2.0-mib')
    end

  end
end

describe Projects::Git::TreesController do
  describe "routing" do

    context "routes to #show" do
      it { get("/import/glib2.0-mib").should route_to("projects/git/trees#show", name_with_owner: 'import/glib2.0-mib') }
      it { get("/import/glib2.0-mib/tree/lib2safe-0.03").should route_to("projects/git/trees#show", name_with_owner: 'import/glib2.0-mib', treeish: 'lib2safe-0.03') }
      # TODO: ???
      # it { get("/import/glib2.0-mib/tree/branch-with.dot/folder_with.dot/path-with.dot").should route_to("projects/git/trees#show", name_with_owner: 'import/glib2.0-mib', treeish: 'branch-with.dot', path: 'folder_with.dot/path-with.dot') }
      # it { get("/import/glib2.0-mib/tree/ветка-с.точкой/папка_с.точкой/путь-с.точкой").should route_to("projects/git/trees#show", name_with_owner: 'import/glib2.0-mib', treeish: 'ветка-с.точкой', path: 'папка_с.точкой/путь-с.точкой') }
      # it { get("/import/glib2.0-mib/tree/branch-with/slash.dot/folder_with.dot/path-with.dot").should route_to("projects/git/trees#show", name_with_owner: 'import/glib2.0-mib', treeish: 'branch-with/slash.dot', path: 'folder_with.dot/path-with.dot') }
      it { get("/import/glib2.0-mib/tree/tag13.52-5").should route_to("projects/git/trees#show", name_with_owner: 'import/glib2.0-mib', treeish: 'tag13.52-5') }
    end

    # TODO write more specs also with slash in branch name!

  end
end
