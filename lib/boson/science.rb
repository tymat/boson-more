require 'boson/view'
require 'boson/scientist'
require 'boson/option_command'
require 'boson/pipe'
require 'boson/pipes'

module Boson
  class Command
    # [*:option_command*] Boolean to wrap a command with an OptionCommand object i.e. allow commands to have options.
    INIT_ATTRIBUTES << :option_command

    module ScienceClassMethods
      attr_accessor :all_option_commands

      def create(name, library)
        super.tap do |obj|
          if @all_option_commands && !%w{get method_missing}.include?(name)
            obj.make_option_command(library)
          end
        end
      end
    end
    extend ScienceClassMethods

    module Science
      # Option parser for command as defined by @render_options.
      def render_option_parser
        option_command? ? Boson::Scientist.option_command(self).option_parser : nil
      end

      def make_option_command(lib=library)
        @option_command = true
        @args = [['*args']] unless args(lib) || arg_size
      end

      def option_command?
        options || render_options || @option_command
      end
    end
    include Science
  end

  class Manager
    module Science
      def create_commands(lib, commands = lib.commands)
        super
        redefine_commands(lib, commands)
      end

      def redefine_commands(lib, commands)
        option_commands = lib.command_objects(commands).select {|e| e.option_command? }
        accepted, rejected = option_commands.partition {|e| e.args(lib) || e.arg_size }
        if @options[:verbose] && rejected.size > 0
          puts "Following commands cannot have options until their arguments are configured: " +
            rejected.map {|e| e.name}.join(', ')
        end
        accepted.each {|cmd| Scientist.redefine_command(lib.namespace_object, cmd) }
      end
    end

    class << self; include Science; end
  end

  # [*:render_options*] Hash of rendering options to pass to OptionParser. If the key :output_class is passed,
  #                     that class's Hirb config will serve as defaults for this rendering hash.
  class Command
    attr_accessor :render_options

    module Science
      def after_initialize(hash)
        if hash[:render_options] && (@render_options = hash.delete(:render_options))[:output_class]
          @render_options = Util.recursive_hash_merge View.class_config(@render_options[:output_class]), @render_options
        end
        super
      end
    end
  end

  if defined? BinRunner
    class BinRunner < Runner
      GLOBAL_OPTIONS.update(
        option_commands: {
          :type=>:boolean,
          :desc=>"Toggles on all commands to be defined as option commands"
        },
        render: {:type=>:boolean,
          :desc=>"Renders a Hirb view from result of command without options"}
      )

      # [:render] Toggles the auto-rendering done for commands that don't have views. Doesn't affect commands that already have views.
      #           Default is false. Also see Auto Rendering section below.
      #
      # ==== Auto Rendering
      # Commands that don't have views (defined via render_options) have their return value auto-rendered as a view as follows:
      # * nil,false and true aren't rendered
      # * arrays are rendered with Hirb's tables
      # * non-arrays are printed with inspect()
      # * Any of these cases can be toggled to render/not render with the global option :render
      # To turn off auto-rendering by default, add a :no_auto_render: true entry to the main config.
      module Science
        def init
          Command.all_option_commands = true if @options[:option_commands]
          super
        end

        def render_output(output)
          if (!Scientist.rendered && !View.silent_object?(output)) ^ @options[:render] ^
            Boson.repo.config[:no_auto_render]
              opts = output.is_a?(String) ? {:method=>'puts'} :
                {:inspect=>!output.is_a?(Array) || (Scientist.global_options || {})[:render] }
              View.render output, opts
          end
        end

        def allowed_argument_error?(err, cmd, args)
          err.class == OptionCommand::CommandArgumentError || super
        end

        def execute_command(cmd, args)
          render_output super
        end
      end

      class <<self
        include Science
      end
    end
  end

  # Additional method attributes:
  # * render_options: Hash to define an OptionParser object for a command's local/global render options (see View).
  module MethodInspector
    METHODS << :render_options
    METHOD_CLASSES[:render_options] = Hash
    SCRAPEABLE_METHODS << :render_options
  end

  module CommentInspector
    EVAL_ATTRIBUTES << :render_options
  end
end
