require 'fileutils'

module Redcar
  class RSense
    def self.menus
      Menu::Builder.build do
        sub_menu "Plugins" do
          sub_menu "RSense" do
            item "code completion", RSense::CodeCompleteCommand
            item "key binding", RSense::ChangeKeyComboCommand
            item "change rsense path", RSense::ChangeRsensePath
          end
        end
      end
    end
    
    def self.completion_kind
      {'CLASS' => 'C', 'MODULE' => 'M', 'CONSTANT' => 'c', 'METHOD' => 'm'}
    end
    
    def self.path
      RSense.storage["rsense_path"] || ""
    end
    
    def self.path=(path)
      RSense.storage["rsense_path"] = path
    end
        
    def self.storage
      @storage ||= Plugin::Storage.new('rsense_plugin')
    end
    
    def self.key_combo      
      RSense.storage["key_combo"] || "Ctrl+/"              
    end
    
    def self.key_combo=(key)
      old_key = key_combo
      old_key_string = Redcar::ApplicationSWT::Menu::BindingTranslator.platform_key_string(old_key)
      item = Redcar::ApplicationSWT::Menu.items[old_key_string]
      Redcar::ApplicationSWT::Menu.items.delete(old_key_string)
      Redcar.app.main_keymap.map.delete(old_key)
      RSense.storage["key_combo"] = key
      Redcar.app.main_keymap.map[key] = RSense::CodeCompleteCommand
      key_string = Redcar::ApplicationSWT::Menu::BindingTranslator.platform_key_string(key)
      item.first.text = item.first.text.split("\t").first + "\t" + key_string
      item.first.set_accelerator(Redcar::ApplicationSWT::Menu::BindingTranslator.key(key_string))
      Redcar::ApplicationSWT::Menu.items[key_string] = item
    end
    
    def self.keymaps
      linwin = Keymap.build("main", [:linux, :windows]) do
        link Redcar::RSense.key_combo, RSense::CodeCompleteCommand
      end

      osx = Keymap.build("main", :osx) do
        link Redcar::RSense.key_combo, RSense::CodeCompleteCommand
      end

      [linwin, osx]
    end
    
    class ChangeKeyComboCommand < Command
      def execute
        result = Application::Dialog.input("Key Combination", "Please enter new key combo (i.e. 'Ctrl+Shift+C')", Redcar::RSense.key_combo) do |text|
          unless text == ""
            nil
          else
            "invalid combination"
          end
      	end
        Redcar::RSense.key_combo = result[:value] if result[:button ] == :ok
      end
    end
    
    class ChangeRsensePath < Command
      def execute
        result = Application::Dialog.input("RSense path", "Please enter Rsense director path (i.e. '/home/sam/rsense-0.3'))", Redcar::RSense.path) do |text|          
          nil            
      	end
        Redcar::RSense.path = result[:value] if result[:button ] == :ok
      end
    end
    
    class RecordComiplerOptions < EditTabCommand
      
    end

    class CodeCompleteCommand < EditTabCommand      
      
      def execute
        path = doc.mirror.path.split(/\/|\\/)
        log(path.join("/"))
        if (path.last.split(".").last =~ /rb|erb/) || path.last.split(".").length == 1
          path[path.length-1]= ".rsense." + path.last
          path = path.join("/")
          line_str = doc.get_line(doc.cursor_line)
          line_str = line_str[0..(line_str.length-2)]
          line_split = line_str.split(/::|\./)        
          prefix = ""
          prefix = line_split.last unless line_str[line_str.length-1].chr =~ /:|\.|>/
          offset_at_line = doc.cursor_line_offset - prefix.length
          log("line_split: #{line_split}")
          log("prefix: #{prefix} offset: #{offset_at_line}")
          doc_str = doc.to_s[0..(doc.cursor_offset-prefix.length-1)] + doc.to_s[doc.cursor_offset..(doc.to_s.length-1)]
          File.open(path, "wb") {|f| f.print doc_str }
          completions = get_completions(path, prefix, offset_at_line)
          
          cur_doc = doc
          builder = Menu::Builder.new do
            completions.each do |current_completion|
              puts log(current_completion[:menu])
              item(current_completion[:word] + "\t" + current_completion[:kind]) do              
                cur_doc.replace(cur_doc.cursor_offset - prefix.length, prefix.length, current_completion[0])
              end
            end
          end
          
          window = Redcar.app.focussed_window
          location = window.focussed_notebook.focussed_tab.controller.edit_view.mate_text.viewer.getTextWidget.getLocationAtOffset(window.focussed_notebook.focussed_tab.controller.edit_view.cursor_offset)
          absolute_x = location.x
          absolute_y = location.y
          location = window.focussed_notebook.focussed_tab.controller.edit_view.mate_text.viewer.getTextWidget.toDisplay(0,0)
          absolute_x += location.x
          absolute_y += location.y
          menu = ApplicationSWT::Menu.new(window.controller, builder.menu, nil, Swt::SWT::POP_UP)
          menu.move(absolute_x, absolute_y)
          menu.show
#          FileUtils.rm(path)
        end
      end
      
      def get_path       
        RSense.path + "/bin/rsense"
      end
      
      def get_completions(temp_path, prefix, offset_at_line)
        line_offset = doc.cursor_line
        words = []
        filename = doc.mirror.path          
        command = "ruby '#{get_path}' 'code-completion' '#{temp_path}' '--location=#{line_offset}+1:#{offset_at_line}+1' '--prefix=#{prefix}' '--detect-project=#{filename}'"
        log(command)
        result = `#{command}`        
        result = result.split("\n")
        completions = []
        result.each do |item|
          if item =~ /^completion: /
            item_a = item.split(" ")
            dict = {}
            dict[:word] = item_a[1]
            if item_a.length > 4
              dict[:menu] = item_a[3]
              dict[:kind] = RSense.completion_kind[item_a[4]]
            end
            completions << dict
          end
        end
        completions        
      end
      1.
      def log(message)
        puts("==> GCCSense: #{message}")
      end
    end
  end
end
