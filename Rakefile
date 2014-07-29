require './importer.rb'
require './pmiddoifier.rb'
require 'fileutils'

desc 'Imports citations from Europe PMC archive'
task :import, [:core] do |t, args|

  files = Dir.glob('data/pmc/*.xml').sort_by{ |f| File.mtime(f) }.reverse

  if args[:core]
    core = args[:core].to_i
    files_count = files.size
    files = files.each_slice(files_count/8).to_a[core]
  end

  files.each_with_index do |file, index|
    puts "Processing #{file} (#{index}/#{files.size})"
    File.open(file) do |f|
      xmls = f.read.lines.slice_before(/<!DOCTYPE/).to_a.map do |parts|
        parts.join
      end
      pb = ProgressBar.create(format: '%a %B %e %t', title: 'XML', total: xmls.size)

      xmls.each_with_index do |xml, index|
        puts "Processing file: #{index}"
        begin
          importer = Importer.new(xml)
          importer.extract
          importer.import
        rescue => e
          error_file = "data/errors/#{File.basename(file)}_#{index}.xml"
          File.open(error_file, 'w+') do |f|
            f.write(xml)
          end
          puts "Something went wrong: #{e.message} #{e.backtrace}"
        end
        puts "Processed #{Importer.files_count} files."
        puts "Processed #{Importer.paper_count} paper citations."
        puts "Processed #{Importer.code_count} code citations."
        puts "Found #{Importer.code_mentions} code mentions."
        pb.increment
      end
      PmidDoifier.sync_to_disk
      pb.finish
    end
    FileUtils.mv(file, "#{file}.done")
  end
end
