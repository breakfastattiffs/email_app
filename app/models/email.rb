class Email < ActiveRecord::Base
  serialize :attachment
  validates :to, presence: true

  module Status
    SENDING = 'Sending'
    SENT = 'Sent'
    TRY_AGAIN = 'Still sending'
    FAILED = 'Failed'
    UNKNOWN = 'Unknown'
  end

end
