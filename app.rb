require 'sinatra'
require 'sinatra/custom_logger'
require 'sinatra/reloader' if settings.development?
require 'dotenv/load' if settings.development?
require 'logger'
require 'slack'

Slack.configure do |config|
  config.token = ENV['SLACK_BOT_TOKEN']
end

module Donut
  class App < Sinatra::Base
    helpers Sinatra::CustomLogger

    ###
    #
    # Custom logging
    #
    ###
    def self.logger
      @logger ||= Logger.new(STDERR)
    end

    configure :development, :production do
      register Sinatra::Reloader
      set :logger, Donut::App.logger
    end

    MODAL_PAYLOAD = {
      "type": "modal",
      "title": {
        "type": "plain_text",
        "text": "Request a task",
        "emoji": true
      },
      "submit": {
        "type": "plain_text",
        "text": "Request",
        "emoji": true
      },
      "close": {
        "type": "plain_text",
        "text": "Cancel",
        "emoji": true
      },
      "blocks": [
        {
          "type": "divider"
        },
        {
          "block_id": "request_task_from",
          "type": "input",
          "optional": false,
          "label": {
            "type": "plain_text",
            "text": "Request task from:"
          },
          "element": {
            "action_id": "conversation_id",
            "type": "conversations_select"
          }
        },
        {
          "block_id": "task_description",
          "type": "input",
          "element": {
            "type": "plain_text_input",
            "action_id": "description"
          },
          "label": {
            "type": "plain_text",
            "text": "Description of task:",
            "emoji": true
          }
        }
      ]
    }.freeze

    def self.requested_task_message_payload(from:, description:)
        {
          "blocks": [
            {
              "block_id": "task_description",
              "type": "context",
              "elements": [
                {
                  "type": "mrkdwn",
                  "text": "*<@#{from}> has requested the following task:* #{description}",
                }
              ]
            },
            {
              "type": "actions",
              "elements": [
                {
                  "type": "button",
                  "text": {
                    "type": "plain_text",
                    "text": "Completed",
                    "emoji": true
                  },
                  "style": "primary",
                  "value": "#{from}:#{description}"
                }
              ]
            },
            {
              "type": "context",
              "elements": [
                {
                  "type": "plain_text",
                  "text": "Click the button once the task has been completed, and we'll notify them that it's been done!",
                  "emoji": true,
                }
              ]
            }
          ]
        }
    end

    ###
    #
    # Routes
    #
    ###
    post '/interactions' do
      payload = JSON.parse(params[:payload], symbolize_names: true)
      Donut::App.logger.info "\n[+] Interaction type #{payload[:type]} recieved."
      Donut::App.logger.info "\n[+] Payload:\n#{JSON.pretty_generate(payload)}"

      client = Slack::Web::Client.new
      actor_id = payload[:user][:id]

      case payload[:type]
      when 'shortcut'
        client.views_open(view: MODAL_PAYLOAD, trigger_id: payload[:trigger_id])
      when 'view_submission'
        assignee_id = payload[:view][:state][:values][:request_task_from][:conversation_id][:selected_conversation]
        description = payload[:view][:state][:values][:task_description][:description][:value]

        # TODO: handle error / early return if either channel_id not found
        actor_channel_id = client.conversations_open(users: actor_id).channel.id
        assignee_channel_id = client.conversations_open(users: assignee_id).channel.id

        # Notify assignee of requested task
        task_request_params = Donut::App.requested_task_message_payload(
          from: actor_id,
          description: description
        ).merge(
          channel: assignee_channel_id
        )
        client.chat_postMessage(task_request_params)

        # Notify actor of successfully requested task
        client.chat_postMessage(
          channel: actor_channel_id,
          text: ":speech_balloon: You have requested <@#{assignee_id}> to do the following task: #{description}"
        )
      end

      200
    end

    # Use this to verify that your server is running and handling requests.
    get '/' do
      'Hello, tofu!'
    end
  end
end
