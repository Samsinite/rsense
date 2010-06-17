require 'fileutils'
require 'stringio'

module Redcar
  class RSense
    
    def self.menus
      unless File.exist?("#{Redcar.root}/plugins/rsense/.rsense")
        puts "no .rsense file detected, creating .rsense file"
        `ruby #{RSense.path}/etc/config.rb > #{Redcar.root}/plugins/rsense/.rsense`        
      end
      Menu::Builder.build do
        sub_menu "Plugins" do
          sub_menu "RSense" do
            item "code completion", RSense::CodeCompleteCommand
            item "type inference", RSense::TypeInferenceCommand
            item "code completion key binding", RSense::ChangeCompletionKeyComboCommand
            item "type inference key binding", RSense::ChangeInferenceKeyComboCommand
          end
        end
      end
    end
    
    def self.completion_kind
      {'CLASS' => 'C', 'MODULE' => 'M', 'CONSTANT' => 'c', 'METHOD' => 'm'}
    end    
    
    def self.path
      "#{Redcar.root}/plugins/rsense/vendor/rsense-0.3"
    end
    
    def self.primitive_command
      if Redcar.platform == :windows
        "java -cp \".;#{RSense.path}/lib/rsense.jar;#{RSense.path}/lib/antlr-runtime-3.2.jar;#{RSense.path}/lib/jruby.jar\" org.cx4a.rsense.Main script \"--home=#{RSense.path}\" --no-prompt --end-mark=END \"--config=#{Redcar.root}/plugins/rsense/.rsense --progress=1\""
      else
        "java -cp '.:#{RSense.path}/lib/rsense.jar:#{RSense.path}/lib/antlr-runtime-3.2.jar:#{RSense.path}/lib/jruby.jar' org.cx4a.rsense.Main script '--home=#{RSense.path}' --no-prompt --end-mark=END --config=#{Redcar.root}/plugins/rsense/.rsense --progress=1"
      end
    end
   
    def self.rsense_io
      if @io
        return @io
      else
        @io_handler = Redcar.app.focussed_window.add_listener(:about_to_close) do |win|
          Redcar::RSense.log("closing io")
          @io.close if @io && !@io.closed?
          Redcar::RSense.rsense_io = nil
          Redcar::RSense.log("io closed")
        end
        @io = IO.popen(primitive_command, 'r+')
      end
    end
    
    def self.rsense_io=(val)
      @io = val
    end
        
    def self.storage
      @storage ||= Plugin::Storage.new('rsense_plugin')
    end
    
    def self.inference_key_combo      
      RSense.storage["inference_key_combo"] || "Ctrl+Shift+/"              
    end
    
    def self.inference_key_combo=(key)
      old_key = key_combo
      old_key_string = Redcar::ApplicationSWT::Menu::BindingTranslator.platform_key_string(old_key)
      item = Redcar::ApplicationSWT::Menu.items[old_key_string]
      Redcar::ApplicationSWT::Menu.items.delete(old_key_string)
      Redcar.app.main_keymap.map.delete(old_key)
      RSense.storage["inference_key_combo"] = key
      Redcar.app.main_keymap.map[key] = RSense::TypeInferenceCommand
      key_string = Redcar::ApplicationSWT::Menu::BindingTranslator.platform_key_string(key)
      item.first.text = item.first.text.split("\t").first + "\t" + key_string
      item.first.set_accelerator(Redcar::ApplicationSWT::Menu::BindingTranslator.key(key_string))
      Redcar::ApplicationSWT::Menu.items[key_string] = item
    end
    
    def self.completion_key_combo      
      RSense.storage["completion_key_combo"] || "Ctrl+/"              
    end
    
    def self.completion_key_combo=(key)
      old_key = key_combo
      old_key_string = Redcar::ApplicationSWT::Menu::BindingTranslator.platform_key_string(old_key)
      item = Redcar::ApplicationSWT::Menu.items[old_key_string]
      Redcar::ApplicationSWT::Menu.items.delete(old_key_string)
      Redcar.app.main_keymap.map.delete(old_key)
      RSense.storage["completion_key_combo"] = key
      Redcar.app.main_keymap.map[key] = RSense::CodeCompleteCommand
      key_string = Redcar::ApplicationSWT::Menu::BindingTranslator.platform_key_string(key)
      item.first.text = item.first.text.split("\t").first + "\t" + key_string
      item.first.set_accelerator(Redcar::ApplicationSWT::Menu::BindingTranslator.key(key_string))
      Redcar::ApplicationSWT::Menu.items[key_string] = item
    end
    
    def self.run_command(command)
      RSense.log("command: #{command}")      
      rsense_io.puts(command)
      result = ""
      while l = rsense_io.gets and /^END/ !~ l          
      result << l
      end        
      result << 'END'
    end
    
    def self.keymaps
      linwin = Keymap.build("main", [:linux, :windows]) do
        link Redcar::RSense.completion_key_combo, RSense::CodeCompleteCommand
        link Redcar::RSense.inference_key_combo, RSense::TypeInferenceCommand
      end

      osx = Keymap.build("main", :osx) do
        link Redcar::RSense.completion_key_combo, RSense::CodeCompleteCommand
        link Redcar::RSense.inference_key_combo, RSense::TypeInferenceCommand
      end

      [linwin, osx]
    end
    
    def self.log(message)
      puts("==> RSense: #{message}")
    end
    
    class ChangeCompletionKeyComboCommand < Command
      def execute
        result = Application::Dialog.input("Code Completion Key Combination", "Please enter new key combo (i.e. 'Ctrl+Shift+C')", Redcar::RSense.completion_key_combo) do |text|
          unless text == ""
            nil
          else
            "invalid combination"
          end
      	end
        Redcar::RSense.completion_key_combo = result[:value] if result[:button ] == :ok
      end
    end
    
    class ChangeInferenceKeyComboCommand < Command
      def execute
        result = Application::Dialog.input("Inference Key Combination", "Please enter new key combo (i.e. 'Ctrl+Shift+C')", Redcar::RSense.inference_key_combo) do |text|
          unless text == ""
            nil
          else
            "invalid combination"
          end
      	end
        Redcar::RSense.inference_key_combo = result[:value] if result[:button ] == :ok
      end
    end
    
    class TypeInferenceCommand < EditTabCommand
      def execute
        return unless doc.mirror
        path = doc.mirror.path.split(/\/|\\/)
        if (path.last.split(".").last =~ /rb|erb/) || path.last.split(".").length == 1
          path[path.length-1]= path.last + "~"
          path = path.join("/")
          cursor_line_number = doc.cursor_line
          cursor_line_str = doc.get_line(cursor_line_number)
          cursor_line_offset = doc.cursor_line_offset
          cursor_offset = doc.cursor_offset
          cursor_line_end_offset = doc.cursor_line_end_offset
          line_str = cursor_line_str.rstrip
          new_line_length = cursor_line_str.length - line_str.length
          line_end_length = line_str.length - cursor_line_offset
          line_str = line_str[0..(cursor_line_offset-1)]          
          line_split = line_str.split(/::|\./)        
          prefix = ""
          prefix = line_split.last unless line_str[line_str.length-1].chr =~ /:|\./
          prefix_start_offset = doc.cursor_line_offset - prefix.length
          
          RSense.log("line_str: #{line_str} length: #{line_str.length}")          
          RSense.log("line_end_length: #{line_end_length}")
          RSense.log("prefix: #{prefix} length: #{prefix.length}")
          RSense.log("prefix_start_offset: #{prefix_start_offset}")
          RSense.log("cursor_offset: #{doc.cursor_offset}")
          RSense.log("cursor_line_offset: #{doc.cursor_line_offset}")
          RSense.log("cursor_line_end_offset: #{doc.cursor_line_end_offset}")
          RSense.log("new_line_length: #{new_line_length}")
          doc_str = doc.to_s[0..(cursor_offset-prefix.length-1)] + doc.to_s[(cursor_offset)..(doc.to_s.length-1)]
          RSense.log("deleted_section: #{doc.to_s[(cursor_offset-prefix.length)..(cursor_line_end_offset-new_line_length-1)]}")

          File.open(path, "wb") {|f| f.print doc_str }
          type = get_type(path, prefix, prefix_start_offset)
          if type            
            tool_tip = Redcar::Application::Dialog.tool_tip(type, :cursor)
          end
          FileUtils.rm(path)
        end
      end
      
      def get_type(temp_path, prefix, offset_at_line)
        line_offset = doc.cursor_line
        words = []
        project = Redcar::Project.window_projects[Redcar.app.focussed_window].path + "/" if Redcar::Project.window_projects[Redcar.app.focussed_window]
        if project
          command = "type-inference '--file=#{temp_path}' '--location=#{line_offset+1}:#{offset_at_line}' '--prefix=#{prefix}' '--detect-project=#{project}'"
        else
          command = "type-inference '--file=#{temp_path}' '--location=#{line_offset+1}:#{offset_at_line}' '--prefix=#{prefix}'"
        end
                
        result = RSense.run_command(command)        
        
        result = result.split("\n")        
        result.each do |item|
          if item =~ /^type: /
            RSense.log("item: #{item}")
            return item.split(" ")[1]
          end
        end
        nil
      end      
    end

    class CodeCompleteCommand < EditTabCommand      
      
      def execute
        return unless doc.mirror
        path = doc.mirror.path.split(/\/|\\/)
        if (path.last.split(".").last =~ /rb|erb/) || path.last.split(".").length == 1
          path[path.length-1]= path.last + "~"
          path = path.join("/")
          cursor_line_number = doc.cursor_line
          cursor_line_str = doc.get_line(cursor_line_number)
          cursor_line_offset = doc.cursor_line_offset
          cursor_offset = doc.cursor_offset
          cursor_line_end_offset = doc.cursor_line_end_offset
          line_str = cursor_line_str.rstrip
          new_line_length = cursor_line_str.length - line_str.length
          line_end_length = line_str.length - cursor_line_offset
          line_str = line_str[0..(cursor_line_offset-1)]          
          line_split = line_str.split(/::|\./)        
          prefix = ""
          prefix = line_split.last unless line_str[line_str.length-1].chr =~ /:|\./
          prefix_start_offset = doc.cursor_line_offset - prefix.length
          
          RSense.log("line_str: #{line_str} length: #{line_str.length}")          
          RSense.log("line_end_length: #{line_end_length}")
          RSense.log("prefix: #{prefix} length: #{prefix.length}")
          RSense.log("prefix_start_offset: #{prefix_start_offset}")
          RSense.log("cursor_offset: #{doc.cursor_offset}")
          RSense.log("cursor_line_offset: #{doc.cursor_line_offset}")
          RSense.log("cursor_line_end_offset: #{doc.cursor_line_end_offset}")
          RSense.log("new_line_length: #{new_line_length}")
          doc_str = doc.to_s[0..(cursor_offset-prefix.length-1)] + doc.to_s[(cursor_offset)..(doc.to_s.length-1)]
          RSense.log("deleted_section: #{doc.to_s[(cursor_offset-prefix.length)..(cursor_line_end_offset-new_line_length-1)]}")

          File.open(path, "wb") {|f| f.print doc_str }
          completions = get_completions(path, prefix, prefix_start_offset)
          
          cur_doc = doc
          builder = Menu::Builder.new do
            completions.each do |completion|
              item(completion[:word] + "\t" + completion[:kind]) do              
                cur_doc.replace(cur_doc.cursor_offset - prefix.length, prefix.length, completion[:word])
              end
            end
          end
          
          Redcar::Application::Dialog.popup_menu(builder.menu, :cursor)
#          FileUtils.rm(path)
        end
      end
      
      def get_completions(temp_path, prefix, offset_at_line)
        line_offset = doc.cursor_line
        words = []
        project = Redcar::Project.window_projects[Redcar.app.focussed_window].path + "/" if Redcar::Project.window_projects[Redcar.app.focussed_window]
        if project
          command = "code-completion '--file=#{temp_path}' '--location=#{line_offset+1}:#{offset_at_line}' '--prefix=#{prefix}' '--detect-project=#{project}'"
        else
          command = "code-completion '--file=#{temp_path}' '--location=#{line_offset+1}:#{offset_at_line}' '--prefix=#{prefix}'"
        end
        
        result = RSense.run_command(command)
        
        result = result.split("\n")
        completions = []
        result.each do |item|
          if item =~ /^completion: /
            RSense.log("item: #{item}")
            item_a = item.split(" ")
            dict = {}
            dict[:word] = item_a[1]
            if item_a.length > 4
              dict[:menu] = item_a[3]
              dict[:kind] = RSense.completion_kind[item_a[4]]
            else
              dict[:menu] = ""
              dict[:kind] = ""
            end
            completions << dict
          end
        end
        completions
      end
    end
  end
end
