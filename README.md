email_app
=========

Rails application with basic email sending functionality

**Project: Email service**

I chose to implement a back-end heavy track. I used Rails to build a simple web application for the UI. I learned Ruby and Rails one and a half years ago. I used Rails because it can get me up and running very quickly with a simple, easy to understand UI as I have no UI skills and also because the language I code in every day is Ruby.  

The application sends e-mails with a plain text body and attachments to multiple comma-separated recipients.

###Design###

I used the third party providers Mandrill and Mailgun. My e-mail sending application is based on Rails’ MVC framework. 

The view is just a simple view for filing out fields of an e-mail. Sending an e-mail really means creating an e-mail record in the database. I have static views for an index page, a view page, and a new email page. Because the views are static, in order to see any changes in the database, one needs to refresh the page. 

The controller is what does most of the heavy lifting. It is responsible for calling the third party APIs to send the email and to check on the status of the e-mail and to update the email database record’s status. An e-mail goes through a simple state machine. The possible states are SENDING, SENT, TRY_AGAIN, FAILED, and UNKNOWN. 

In my implementation, to reduce the problem to a simpler architecture, if an e-mail is meant for multiple recipients, I split the sending into an e-mail for each person. This means the e-mails cannot be used as group threads. This is a source for future improvement.  

I used Mandrill as the primary e-mail sending service, and if that did not work, fell back to using Mailgun. 
An e-mail starts off getting sent by Mandrill. It goes through the following states after calling Mandrill’s send api:

1. The send api might immediately return a “sent” status. In this case, the e-mail db record is updated to SENT. It is successful. We no longer do anything.
2. Most of the time, the Mandrill API returns “queued,” and the email’s state is updated to SENDING.
3. If SENDING, the controller forks a process that will start polling Mandrill’s info api for the status of the email. The polling will stop when the api returns either sent, or bounced/failed. We fork a process because we do not want the UI to hang forever as the controller polls for the email status as we do not know how long before the email gets processed. Currently, I have a default timeout of 300 seconds, so that the polling doesn’t go on forever. If the polling times out, the e-mail is put into a TRY_AGAIN state.
4. If polling returns that the status of the email is “sent,” we update the e-mail’s database record to SENT.
5. A return status of bounced/failed puts the e-mail into a TRY_AGAIN state. In the current logic, there is no check for what kind of bounce/failure happened, whether it was a permanent form of failure or a temporary one that we can recover from. Whatever failure, we immediately try to send the e-mail again using the Mailgun api. This default fall back behavior simplifies the state machine, and is a spot for future refinement. 

If the e-mail goes into the TRY_AGAIN, we send an e-mail using Mailgun. We start the e-mail sending process through Mailgun in a new process by forking.  An e-mail sent through Mailgun goes through the same states as 1 through 5 above except for two differences. 

For number 3, the polling of the Mailgun email status times out after 600 seconds instead of 300. If the status polling times out, the e-mail’s state is updated to FAILED, not TRY_AGAIN, since Mailgun is our sender of last resort.
For number 5, if the e-mail status returns as anything but sent, we mark the e-mail as FAILED.
###Core Code###
**app/config/email_provider.yml** 
Configuration for e-mail service providers. Contains settings for the services such as key and user and url.

**app/classes/generic_email_provider**
This class has knowledge of the two services Mandrill and Mailgun. It sets up the forking of processes and calls the third party APIs inside of the forked processes.

**app/classes/http_utils.rb**
A general utility class for calling http post and http get requests. This class uses Ruby’s net/http class.

**app/classes/mandrill_api.rb**
This class provides the abstraction for Mandrill’s API. It builds the JSON body and calls the API using http_utils.http_post

**app/classes/mailgun_api.rb**
This class provides the abstraction for Mailgun’s API. Mailgun’s API for sending e-mails does not use JSON with post requests. The class creates the needed multi-part form one uses as the body for the post request to Mailgun’s APIs. This was more time-consuming than I expected as the formatting (like number of carriage returns) needs to be exactly right for the post data to work. An example Mailgun multi-part form format:
```
--42ae26380478e262fbd24b0aa1e9e039MultipartFormDataBoundary
Content-Disposition: form-data; name="to"
 
email@email.com
--42ae26380478e262fbd24b0aa1e9e039MultipartFormDataBoundary
Content-Disposition: form-data; name="subject"

Subject Line
--42ae26380478e262fbd24b0aa1e9e039MultipartFormDataBoundary
Content-Disposition: form-data; name="from"
 
postmaster@sandbox.mailgun.org
--42ae26380478e262fbd24b0aa1e9e039MultipartFormDataBoundary
Content-Disposition: form-data; name="text"

Message body
 --42ae26380478e262fbd24b0aa1e9e039MultipartFormDataBoundary
Content-Disposition: form-data; name="attachment[]"; filename="world.txt"
Content-Type: text/plain

<attachment contents> 
--42ae26380478e262fbd24b0aa1e9e039MultipartFormDataBoundary
Content-Disposition: form-data; name="attachment[]"; filename="hello.txt"
Content-Type: text/plain

<attachment contents>
--42ae26380478e262fbd24b0aa1e9e039MultipartFormDataBoundary--
```



