# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe JobsController do
  let(:project) { projects(:test) }
  let(:stage) { stages(:test_staging) }
  let(:command) { "echo hi" }
  let(:job) { Job.create!(command: command, project: project, user: user) }
  let(:job_service) { stub(execute!: nil) }

  as_a_viewer do
    describe "#enabled" do
      it "is no_content when enabled" do
        JobExecution.expects(:enabled).returns true
        get :enabled
        assert_response :no_content
      end

      it "is accepted when disabled" do
        refute JobExecution.enabled
        get :enabled
        assert_response :accepted
      end
    end
  end

  as_a_viewer do
    describe "#index" do
      before { get :index, params: {project_id: project.to_param } }

      it "renders the template" do
        assert_template :index
      end
    end

    describe "#show" do
      describe 'with a job' do
        before { get :show, params: {project_id: project.to_param, id: job } }

        it "renders the template" do
          assert_template :show
        end
      end

      describe 'with a running job' do
        before { get :show, params: {project_id: project.to_param, id: jobs(:running_test) } }

        it "renders the template" do
          assert_template :show
        end
      end

      it "fails with unknown job" do
        assert_raises ActiveRecord::RecordNotFound do
          get :show, params: {project_id: project.to_param, id: "job:nope"}
        end
      end

      describe "with format .text" do
        before { get :show, params: {format: :text, project_id: project.to_param, id: job } }

        it "responds with a plain text file" do
          assert_equal response.content_type, "text/plain"
        end

        it "responds with a .log file" do
          assert response.header["Content-Disposition"] =~ /\.log"$/
        end
      end
    end

    unauthorized :post, :create, project_id: :foo
    unauthorized :delete, :destroy, project_id: :foo, id: 1
  end

  as_a_project_deployer do
    unauthorized :post, :create, project_id: :foo

    describe "#destroy" do
      it "deletes the job" do
        delete :destroy, params: {project_id: project.to_param, id: job}
        assert_redirected_to [project, job]
        flash[:notice].must_equal 'Cancelled!'
      end

      it "is unauthorized when not allowed" do
        job.update_column(:user_id, users(:admin).id)
        delete :destroy, params: {project_id: project.to_param, id: job}
        assert_redirected_to [project, job]
        flash[:error].must_equal "You are not allowed to stop this job."
      end

      it "redirects to passed path" do
        delete :destroy, params: {project_id: project.to_param, id: job, redirect_to: '/ping'}
        assert_redirected_to '/ping'
      end
    end
  end

  as_a_project_admin do
    describe "#new" do
      it "renders" do
        get :new, params: {project_id: project}
        assert_template :new
      end
    end

    describe "#create" do
      let(:command_ids) { [] }

      def create
        post :create, params: {
          commands: {ids: command_ids},
          job: {
            command: command,
            commit: "master"
          },
          project_id: project.to_param
        }
      end

      it "creates a job and starts it" do
        JobExecution.expects(:start_job)
        assert_difference('Job.count') { create }
        assert_redirected_to project_job_path(project, Job.last)
      end

      it "keeps commands in correct order" do
        command_ids.replace([commands(:global).id, commands(:echo).id])
        create
        Job.last.command.must_equal("t\necho hello\necho hi")
      end

      it "fails to create job when locked" do
        JobExecution.expects(:start_job).never
        Job.any_instance.expects(:save).returns(false)
        refute_difference('Job.count') { create }
        assert_template :new
      end
    end
  end
end
