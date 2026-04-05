# frozen_string_literal: true

require 'webrick'
require 'uri'

module RubynCode
  module Auth
    class Server
      LISTEN_HOST = '127.0.0.1'
      LISTEN_PORT = 19_275

      class CallbackTimeout < RubynCode::AuthenticationError
      end

      def initialize
        @result = nil
        @mutex = Mutex.new
        @condvar = ConditionVariable.new
      end

      def wait_for_callback(timeout: 120)
        server = build_server
        thread = Thread.new { server.start }

        @mutex.synchronize do
          @condvar.wait(@mutex, timeout) until @result || timed_out?(timeout)
        end

        server.shutdown
        thread.join(5)

        raise CallbackTimeout, "OAuth callback was not received within #{timeout} seconds" unless @result

        @result
      end

      private

      def build_server
        logger = WEBrick::Log.new($stderr, WEBrick::Log::WARN)
        access_log = []

        server = WEBrick::HTTPServer.new(
          BindAddress: LISTEN_HOST,
          Port: LISTEN_PORT,
          Logger: logger,
          AccessLog: access_log
        )

        server.mount_proc('/callback') do |req, res|
          handle_callback(req, res, server)
        end

        server
      end

      def handle_callback(req, res, server)
        params = parse_query(req.query_string)

        if params['code']
          handle_success_callback(params, res)
        else
          handle_error_callback(params, res)
        end

        Thread.new { sleep(0.5) && server.shutdown }
      end

      def handle_success_callback(params, res)
        @mutex.synchronize do
          @result = { code: params['code'], state: params['state'] }
          @condvar.signal
        end
        res.status = 200
        res.content_type = 'text/html; charset=utf-8'
        res.body = success_html
      end

      def handle_error_callback(params, res)
        res.status = 400
        res.content_type = 'text/html; charset=utf-8'
        res.body = error_html(params['error'] || 'unknown',
                              params['error_description'] || 'No authorization code received')
        @mutex.synchronize { @condvar.signal }
      end

      def parse_query(query_string)
        return {} unless query_string

        URI.decode_www_form(query_string).to_h
      end

      def timed_out?(timeout)
        @start_time ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
        elapsed >= timeout
      end

      def success_html
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head><title>rubyn-code</title></head>
          <body style="font-family: system-ui, sans-serif; text-align: center; padding: 60px;">
            <h1>Authenticated!</h1>
            <p>You can close this tab and return to your terminal.</p>
          </body>
          </html>
        HTML
      end

      def error_html(error, description)
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head><title>rubyn-code - Error</title></head>
          <body style="font-family: system-ui, sans-serif; text-align: center; padding: 60px;">
            <h1>Authentication Failed</h1>
            <p><strong>#{WEBrick::HTMLUtils.escape(error)}</strong></p>
            <p>#{WEBrick::HTMLUtils.escape(description)}</p>
          </body>
          </html>
        HTML
      end
    end
  end
end
