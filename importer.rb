require './cayley.rb'
require 'nokogiri'
require 'pry'
require 'rest_client'
require 'ruby-progressbar'

class Importer
  PMID2DOI = 'data/pmid2doi.json'
  def self.pmid2doi(pmid)
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
      @pmid2doi ||= JSON.parse(open(PMID2DOI).read)
    end

    if @pmid2doi[pmid]
      @pmid2doi[pmid]
    else
      doi = remote_pmid2doi(pmid)
      if doi
        @pmid2doi[pmid] = doi
      end
    end
  end

  def self.remote_pmid2doi(pmid)
    response = RestClient.get "http://www.pmid2doi.org/rest/json/doi/#{pmid}", {accept: :json}
    doi = response['doi']
  rescue
  end

  def initialize(xml)
    @xml = Nokogiri::XML(xml)
    @xml.remove_namespaces!
    @cayley = Cayley.new
    @doi = @xml.css("article-id[pub-id-type=\"doi\"]")
    if @doi.empty? || @doi.text.empty?
      raise 'DOI for originating paper not found.'
    else
      @doi = @doi.text
    end
  end

  def extract
    @links = @xml.css("ext-link[ext-link-type=\"uri\"]").map do |link|
      href = link.attr('href')
      if href =~ /(github.com|googlecode.com|sourceforge.net|bitbucket.com|cran.r-project.org)/
        {predicate: 'code', object: href.gsub(/^https?:\/\//, '')}
      elsif href =~ /dx.doi.org\/(.*)/
        {predicate: 'paper', object: $1} unless $1.empty?
      end
    end.compact
  end

  def import
    @links.each do |link|
      link[:subject] = @doi
      puts "Writing: #{link.to_a}"
      @cayley.write(link[:subject], link[:predicate], link[:object])
    end
  end
end

files = Dir.glob('data/pmc/*.xml')

files.each do |file|
  puts "Processing #{file}"

  xmls = open(file).read.lines.slice_before(/<!DOCTYPE/).to_a.map do |parts|
    parts.join
  end
  pb = ProgressBar.create(format: '%a %B %e %t', title: 'XML', total: xmls.size)

  xmls.each do |xml|
    begin
      importer = Importer.new(xml)
      importer.extract
      importer.import
    rescue => e
      puts "Something went wrong: #{e.message}"
    end
    pb.increment
  end
  pb.finish
end
