# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # Set or report the Chisel intensity. Chisel is the opt-in "write the
      # minimum that works" enforcement layer; it is off by default and only
      # changes the agent's behavior once turned on here.
      class Chisel < Base
        def self.command_name = '/chisel'
        def self.description = 'Set or show Chisel intensity (off|lite|full|ultra)'

        def execute(args, ctx)
          arg = args.first
          return report(ctx) if arg.nil? || arg.strip.empty?

          mode = arg.strip.downcase
          return reject(mode, ctx) unless RubynCode::Chisel.valid?(mode)

          persist(mode, ctx)
        end

        private

        def report(ctx)
          current = RubynCode::Chisel.mode
          ctx.renderer.info("Chisel: #{current}")
          ctx.renderer.info("Modes: #{RubynCode::Chisel::MODES.join(' | ')}")
          ctx.renderer.info('Set with: /chisel full')
        end

        def persist(mode, ctx)
          settings = Config::Settings.new
          settings.set(RubynCode::Chisel::CONFIG_KEY, mode)
          settings.save!
          ctx.renderer.info(confirmation(mode))
        end

        def confirmation(mode)
          return 'Chisel off — agent behaves normally.' if mode == 'off'

          "Chisel set to #{mode} — the agent will favor writing the minimum that works."
        end

        def reject(mode, ctx)
          ctx.renderer.warning("Unknown Chisel mode: #{mode}")
          ctx.renderer.info("Valid modes: #{RubynCode::Chisel::MODES.join(', ')}")
        end
      end
    end
  end
end
