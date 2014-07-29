require 'csv'

class PmidDoifier
  class << self
    PMID2DOI = 'data/pmid2doi.json'
    PMID2DOI_API = 'http://www.pmid2doi.org/rest/json/batch/doi?pmids='
    PMID2DOI_ALF = 'data/doi_pmid.csv'

    attr_accessor :pmid2doi

    # Converts as much PMIDs in to DOIs as machinely possible
    # and return unresolved PMIDs too.
    def pmids2doi(pmids)
      pmids = [pmids] unless pmids.is_a?(Array)

      lost_pmids = []

      dois = pmids.map do |pmid|
        doi = pmid2doi[pmid]
        if doi
          'doi:' + doi
        else
          lost_pmids << pmid
          nil
        end
      end

      pairs = nil # remote_pmids2doi(lost_pmids)
      if pairs
        pairs.each do |pair|
          dois << 'doi:' + pair['doi']
          pmid2doi[pair['pmid']] = pair['doi']
          lost_pmids.delete(pair['doi'])
        end
      end

      dois.compact + lost_pmids.map{|pmid| 'pmid:' + pmid.to_s}
    end

    def sync_to_disk
      File.open(PMID2DOI, 'w+:UTF-8') do |f|
        f.write pmid2doi.to_json
      end
    end

    private

    def parse_metadata(xml)
      pairs = {}
      xml = Nokogiri::XML(File.open(xml).read)
      xml.css('PMC_ARTICLE').each do |article|
        doi = article.at('DOI').text
        pmid = article.css('pmid').text

        unless doi.empty?
          pairs[pmid] = doi
        end
      end
      pairs
    end

    def pmid2doi
      xmls = Dir.glob('data/pmc_metadata/*.xml')
      unless @pmid2doi || File.exists?(PMID2DOI)
        @pmid2doi = {}

        # Import from PMC XMLs
        xmls.each do |xml|
          @pmid2doi.merge! parse_metadata(xml)
        end

        # Import from Alf's list
        CSV.foreach(PMID2DOI_ALF, encoding: 'UTF-8') do |row|
          doi = row[0]
          pmid = row[1]
          @pmid2doi[pmid] = doi
        end

        sync_to_disk
      else
        @pmid2doi ||= JSON.parse(open(PMID2DOI).read.force_encoding('utf-8'))
      end
      @pmid2doi
    end

    def remote_pmids2doi(pmids)
      return nil if pmids.empty?
      pmids.map!(&:to_i)
      response = RestClient.get "#{PMID2DOI_API}#{pmids.to_json}", {accept: :json}
      JSON.parse(response)
    rescue
    end
  end
end
