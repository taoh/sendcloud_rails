module Sendcloud
  class Deliverer

    attr_accessor :settings

    def initialize(settings)
      self.settings = settings
    end

    def api_user
      self.settings[:api_user]
    end

    def api_key
      self.settings[:api_key]
    end

    def api_url
      self.settings[:api_url]
    end

    def deliver!(rails_message)
      options = build_sendcloud_message_for(rails_message)
      response = sendcloud_client.send_message options
      # Rails.logger.info("from:#{options[:from]} to:#{options[:to]} res:#{response}")
      rails_message.api_response = response
      if response.code == 200
        sendcloud_message_id = JSON.parse(response.to_str)["id"]
        rails_message.message_id = sendcloud_message_id
      end

      response
    end

    private

    def build_sendcloud_message_for(rails_message)
      sendcloud_message = build_basic_sendcloud_message_for rails_message
      transform_sendcloud_attributes_from_rails rails_message, sendcloud_message
      remove_empty_values sendcloud_message

      sendcloud_message
    end

    def build_basic_sendcloud_message_for(rails_message)
      sendcloud_message = {
        apiUser: api_user,
        apiKey: api_key,
        from: rails_message[:from].formatted.join(";"),
        to: rails_message[:to].formatted.join(";"),
        subject: rails_message.subject,
        html: extract_html(rails_message),
        plain: extract_text(rails_message),
        fromName: rails_message['from-name']
      }

      [:cc, :bcc].each do |key|
        sendcloud_message[key] = rails_message[key].formatted if rails_message[key]
      end

      return sendcloud_message
    end

    def transform_sendcloud_attributes_from_rails(rails_message, sendcloud_message)
      transform_reply_to rails_message, sendcloud_message if rails_message.reply_to
      transform_label_id rails_message, sendcloud_message
      transform_custom_headers rails_message, sendcloud_message
    end

    def transform_reply_to(rails_message, sendcloud_message)
      sendcloud_message['h:Reply-To'] = rails_message[:reply_to].formatted.first
    end

    def transform_label_id(rails_message, sendcloud_message)
      id = label_id(rails_message)
      sendcloud_message['labelId'] = id if id
    end

    def extract_html(rails_message)
      if rails_message.html_part
        rails_message.html_part.body.decoded
      else
        rails_message.content_type =~ /text\/html/ ? rails_message.body.decoded : nil
      end
    end

    def extract_text(rails_message)
      if rails_message.multipart?
        rails_message.text_part ? rails_message.text_part.body.decoded : nil
      else
        rails_message.content_type =~ /text\/plain/ ? rails_message.body.decoded : nil
      end
    end

    def transform_custom_headers(rails_message, sendcloud_message)
      rails_message.sendcloud_headers.try(:each) do |name, value|
        sendcloud_message["h:#{name}"] = value
      end
    end

    def remove_empty_values(sendcloud_message)
      sendcloud_message.delete_if { |key, value| value.nil? }
    end

    def sendcloud_client
      @sendcloud_client ||= Client.new(api_url)
    end

    def label_id rails_message
      rails_message.header.fields.find { |f| f.name == 'label-id' }.try :value
    end

  end
end

ActionMailer::Base.add_delivery_method :sendcloud, Sendcloud::Deliverer
