require './cayley.rb'
require 'nokogiri'
require 'pry'
require 'rest_client'
require 'ruby-progressbar'
require 'json'
require './pmiddoifier.rb'

class Importer
  class << self
    attr_accessor :files_count, :paper_count, :code_count, :code_mentions
  end

  # Class-level instance variables
  @files_count = 0
  @paper_count = 0
  @code_count = 0
  @code_mentions = 0

  def initialize(xml)
    @xml = Nokogiri::XML(xml)
    @xml.remove_namespaces!
    @cayley = Cayley.new

    @doi = @xml.at_css("article-id[pub-id-type=\"doi\"]")
    if @doi && !@doi.text.empty?
      @subject = 'doi:' + @doi.text
    end

    unless @subject
      @pmid = @xml.at_css("article-id[pub-id-type=\"pmid\"]")
      if @pmid && !@pmid.text.empty?
        @subject = 'pmid:' + @pmid.text
        # Try to convert PMID to DOI
        begin
          @subject = 'doi:' + PmidDoifier.pmids2doi(@pmid.text)[0]
        rescue
        end
      end
    end

    unless @subject
      @pmcid = @xml.at_css("article-id[pub-id-type=\"pmcid\"]")
      if @pmcid && !@pmcid.text.empty?
        @subject = 'pmcid:' + @pmcid.text
      end
    end

    unless @subject
      raise 'Unique id for paper not found (missing PMID & DOI)'
    end
    Importer.files_count += 1
  end

  def extract
    number = @xml.text.scan(/(github.com|googlecode.com|sourceforge.net|bitbucket.com|cran.r-project.org)/).size
    Importer.code_mentions += number

    @links = @xml.css("ext-link[ext-link-type=\"uri\"]").map do |link|
      href = link.attr('href')
      if href =~ /(github.com|googlecode.com|sourceforge.net|bitbucket.com|cran.r-project.org)/
        url = href.gsub(/^https?:\/\//, '')
        {predicate: 'code', object: clean(url)}
      elsif href =~ /dx.doi.org\/(.*)/
        doi = 'doi:' + $1
        {predicate: 'paper', object: doi} unless doi.empty?
      end
    end

    pmids = @xml.css('mixed-citation pub-id[pub-id-type="pmid"], element-citation pub-id[pub-id-type="pmid"]').map do |pmid|
      pmid = pmid.text
    end

    dois = PmidDoifier.pmids2doi(pmids).map do |doi|
      {predicate: 'paper', object: doi}
    end

    @links.concat(dois)
    @links.compact!
  end

  def import
    code_found = false
    if @links.empty?
      puts "No links in #{@subject}"
    end
    @links.map! do |link|
      # To skip objects like: 10.1107/S1600536814011209/rk2427Isup2.hkl
      next if link[:object] =~ /.*\/.*\/.*sup.*/

      if link[:predicate] == 'code'
        code_found = true
        Importer.code_count += 1
      elsif link[:predicate] == 'paper'
        Importer.paper_count += 1
      end
     
      [@subject, link[:predicate], link[:object]]
    end.compact!

    @cayley.write(@links) if code_found
  end

  private

  def clean(url)
    url.gsub(/\/$/, '')
  end
end
