#!/usr/bin/env ruby
require 'xcodeproj'

class String
    def include_any?(array)
      array.any? {|i| self.include? i}
    end
end

def addfiles (direc, current_group, main_target, compiler_flags)
    Dir.glob(direc) do |item|
        next if item == '.' or item == '.DS_Store'
            if File.directory?(item)
                new_folder = File.basename(item)
                created_group = current_group.new_group(new_folder)
                addfiles("#{item}/*", created_group, main_target, compiler_flags)
        else
            i = current_group.new_file(item)
            if item.include_any?([".m", ".mm", ".c"]) && !item.include_any?([".md", ".modulemap"])
                match_index = compiler_flags.find_index(compiler_flags.find { |i| item.include?(i[0]) })
                if match_index
                    main_target.add_file_references([i], compiler_flags.values[match_index])
                else
                    main_target.add_file_references([i])
                end
            end
        end
    end
end

### Start of project specific script ###
target_name = 'TestProject'
project_path = "#{__dir__}/#{target_name}.xcodeproj"
deployment_target = '10.0'
project = Xcodeproj::Project.open(project_path)
library_path = "#{__dir__}/Libraries"

main_target = nil
project.targets.each do |target|
    if target.name == target_name
        main_target = target
    end
end

puts "\n"
if !main_target.nil?
    puts "Primary target: #{main_target.name}"
    main_target.deployment_target = deployment_target
    puts "Set deployment target of #{deployment_target}"
else
    puts "Primary target not found"
    exit 1
end

# Define file specific compiler flags
compiler_flags = {
    'GULSwizzledObject' => '-fno-objc-arc',
}

puts "\n"
# Add Libraries and files to project
if !project['Libraries']
    # If no existing libraries group, add one.
    library_group = project.new_group('Libraries')
    puts 'Created Libraries group.'
    # Not bothering to handle if Libaries group is empty.
    addfiles("#{library_path}/**", library_group, main_target, compiler_flags)
    puts "Added files to Libraries group."
else
    puts 'Libraries group already created, skipping...'
end

puts "\n"
# Add Firebase GoogleService-Info.plist
path = "#{__dir__}/GoogleService-Info.plist"
if File.file?(path)
    if !project[target_name].files.find { |i| i.path.include?("GoogleService-Info.plist") }
        file = project[target_name].new_file(path)
        main_target.add_file_references([file])
        puts "Added GoogleService-Info.plist"
    else
        puts "GoogleService-Info.plist already added, skipping..."
    end
else
    puts "GoogleService-Info.plist not found at \n#{path}"
end

puts "\n"
# Set preprocessor macros and set header search path
puts "Configuring build settings..."

def set_build_setting(setting, value)
    if setting.nil?
        setting = value
    elsif !setting.include?(value[0])
        if setting.instance_of? String
            setting += value.join(" ")
        elsif setting.instance_of? Array
            setting.concat(value)
        end
    end
end

main_target.build_configurations.each do |config|
    preprocessor_macros = [
        'FIRCore_VERSION=6.10.1',
        'Firebase_VERSION=6.31.0',
        'PB_FIELD_32BIT=1',
        'PB_NO_PACKED_STRUCTS=1',
        'PB_ENABLE_MALLOC=1',
        'DISPLAY_VERSION=4.5.0',
        'CLS_SDK_NAME="Crashlytics tvOS SDK"',
        'FIRInstallations_LIB_VERSION=1.7.0',
        'GDTCOR_VERSION=7.3.0'
    ]
    linker_flags = [
        '$(OTHER_LDFLAGS)',
        '-ObjC',
    ]
    header_search_paths = [
        "#{library_path}/**",
    ]

    config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = set_build_setting(
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'], 
        preprocessor_macros
    )
    config.build_settings['OTHER_LDFLAGS'] = set_build_setting(
        config.build_settings['OTHER_LDFLAGS'],
        linker_flags
    )
    config.build_settings['HEADER_SEARCH_PATHS'] = set_build_setting(
        config.build_settings['HEADER_SEARCH_PATHS'],
        header_search_paths
    )
    config.build_settings['CLANG_ENABLE_MODULES'] = "YES"
end

puts "\n"
# Add scripts and input files

if !main_target.shell_script_build_phases.find { |s| s.name == "FirebaseCrashlytics" }
    puts "Adding scripts and input files..."
    shell_script_build_phase = main_target.new_shell_script_build_phase("FirebaseCrashlytics")
    shell_script_build_phase.shell_script = "#{library_path}/FirebaseCrashlytics/run"
    shell_script_build_phase.input_paths = [
        "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}",
        "$(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)"
    ]
else
    puts "Scripts and input files already added, skipping..."
end

puts "\n"
# Save project
project.save()
puts "Done."
