require 'securerandom'
require "net/http"
require "uri"
require 'mail'
require 'pp'

class EmailsController < ApplicationController
  before_action :set_email, only: [:show, :edit, :update, :destroy]

  # GET /emails
  # GET /emails.json
  def index
    @emails = Email.all
  end

  # GET /emails/1
  # GET /emails/1.json
  def show
  end

  # GET /emails/new
  def new
    @email = Email.new
  end

  # GET /emails/1/edit
  def edit
  end

  # POST /emails
  # POST /emails.json
  def create
    @email = Email.new(email_params)
    # @attachment_location = Rails.root.join('public', 'uploads').to_s
    #
    # attachments = email_params[:attachment]
    # if attachments
    #   @file_id = Time.now.to_i.to_s
    #   attachments.map do |a|
    #     File.open(File.join(@attachment_location, @file_id + a.original_filename), 'wb') do |file|
    #       file.write(a.read)
    #     end
    #   end
    # end

    parsed_address_list = Mail::AddressList.new(email_params[:to])
    attachment_string = email_params[:attachment].map do |file|
      file.original_filename
    end.join(",\n") if email_params[:attachment]

    separate_emails = parsed_address_list.addresses.map do |a|
      email = email_params
      email[:to] = a.to_s
      email[:attachment] = attachment_string
      #email[:attachment_id] = @file_id
      @email = Email.create(email)
      api_params = email_params
      api_params[:to] = a.to_s

      GenericEmailProvider.new.send_message(api_params, @email)
    end

    respond_to do |format|
      if @email.save
        format.html { redirect_to @email, notice: 'Email was successfully created.' }
        format.json { render :show, status: :created, location: @email }
      else
        format.html { render :new }
        format.json { render json: @email.errors, status: :unprocessable_entity }
      end
    end
  end

# PATCH/PUT /emails/1
# PATCH/PUT /emails/1.json
  def update

    respond_to do |format|
      if @email.update(email_params)
        format.html { redirect_to @email, notice: 'Email was successfully updated.' }
        format.json { render :show, status: :ok, location: @email }
      else
        format.html { render :edit }
        format.json { render json: @email.errors, status: :unprocessable_entity }
      end
    end
  end

# DELETE /emails/1
# DELETE /emails/1.json
  def destroy
    @email.destroy
    respond_to do |format|
      format.html { redirect_to emails_url, notice: 'Email was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
# Use callbacks to share common setup or constraints between actions.
  def set_email
    @email = Email.find(params[:id])
  end

# Never trust parameters from the scary internet, only allow the white list through.
  def email_params
    params.require(:email).permit(:to, :subject, :body, :attachment => [])
  end
end
