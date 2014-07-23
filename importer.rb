require './cayley.rb'
require 'nokogiri'
require 'pry'
require 'rest_client'
require 'ruby-progressbar'
require 'json'

class Importer
  class << self
    attr_accessor :files_count, :paper_count, :code_count, :pmid2doi

    # Converts as much PMIDs in to DOIs as machinely possible
    def pmids2doi(pmids)
      pmids = [pmids] unless pmids.is_a?(Array)

      xmls = Dir.glob('data/pmc_metadata/*.xml')
      unless @pmid2doi || File.exists?(PMID2DOI)
        @pmid2doi = {}
        xmls.each do |xml|
          xml = Nokogiri::XML(File.open(xml).read)
          xml.css('PMC_ARTICLE').each do |article|
            doi = article.at('DOI').text
            pmid = article.css('pmid').text

            unless doi.empty?
              @pmid2doi[pmid] = doi
            end
          end
        end
      else
        @pmid2doi ||= JSON.parse(open(PMID2DOI).read.force_encoding('utf-8'))
      end

      lost_pmids = []

      dois = pmids.map do |pmid|
        if @pmid2doi[pmid]
          @pmid2doi[pmid]
        else
          lost_pmids << pmid
          nil
        end
      end

      pairs = remote_pmids2doi(lost_pmids)
      if pairs
        dois.concat(pairs.map do |pair|
          @pmid2doi[pair['pmid']] = pair['doi']
          pair['doi']
        end)
      end

      dois.compact
    end


    def remote_pmids2doi(pmids)
      pmids.map!(&:to_i)
      response = RestClient.get "http://www.pmid2doi.org/rest/json/batch/doi?pmids=#{pmids.to_json}", {accept: :json}
      JSON.parse(response)
    rescue
    end

  end

  # Class-level instance variables
  @files_count = 0
  @paper_count = 0
  @code_count = 0

  PMID2DOI = 'data/pmid2doi.json'


  def initialize(xml)
    @xml = Nokogiri::XML(xml)
    @xml.remove_namespaces!
    @cayley = Cayley.new
    @doi = @xml.css("article-id[pub-id-type=\"doi\"]").first
    @pmid = @xml.css("article-id[pub-id-type=\"pmid\"]").first
    if @doi && !@doi.text.empty?
      @doi = @doi.text
    elsif @pmid && !@pmid.text.empty?
      @doi = pmids2doi(pmid)[0]
    end

    unless @doi
      raise 'DOI for originating paper not found.'
    end
    Importer.files_count += 1
  end

  def extract
    @links = @xml.css("ext-link[ext-link-type=\"uri\"]").map do |link|
      href = link.attr('href')
      if href =~ /(github.com|googlecode.com|sourceforge.net|bitbucket.com|cran.r-project.org)/
        {predicate: 'code', object: href.gsub(/^https?:\/\//, '')}
      elsif href =~ /dx.doi.org\/(.*)/
        doi = $1
        {predicate: 'paper', object: doi} unless doi.empty?
      end
    end

    pmids = @xml.css('mixed-citation pub-id[pub-id-type="pmid"], element-citation pub-id[pub-id-type="pmid"]').map do |pmid|
      pmid = pmid.text
    end

    dois = self.class.pmids2doi(pmids).map do |doi|
      {predicate: 'paper', object: doi}
    end

    @links.concat(dois)
    @links.compact!
  end

  def import
    if @links.empty?
      puts "No links in #{@doi}"
    end
    @links.each do |link|
      # To skip objects like: 10.1107/S1600536814011209/rk2427Isup2.hkl
      next if link[:object] =~ /.*\/.*\/.*sup.*/

      if link[:predicate] == 'code'
        Importer.code_count += 1
      elsif link[:predicate] == 'paper'
        Importer.paper_count += 1
      end

      @cayley.write(@doi, link[:predicate], link[:object])
    end
  end
end

files = Dir.glob('data/pmc/*.xml')

files.each do |file|
  puts "Processing #{file}"

  File.open(file) do |f|
    xmls = f.read.lines.slice_before(/<!DOCTYPE/).to_a.map do |parts|
      parts.join
    end
    pb = ProgressBar.create(format: '%a %B %e %t', title: 'XML', total: xmls.size)

    xmls.each_with_index do |xml, index|
      puts "Processing file: #{index}"
      GC.start
      begin
        importer = Importer.new(xml)
        importer.extract
        importer.import
      rescue => e
        puts "Something went wrong: #{e.message} #{e.backtrace}"
      end
      puts "Processed #{Importer.files_count} files."
      puts "Processed #{Importer.paper_count} paper citations."
      puts "Processed #{Importer.code_count} code citations."
      pb.increment
    end

    # Sync new DOIs to disk
    File.open('data/pmid2doi.json', 'w+:UTF-8') do |f|
      f.write Importer.pmid2doi.to_json
    end
    pb.finish
  end


end
