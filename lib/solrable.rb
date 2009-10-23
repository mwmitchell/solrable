module Solrable
  
  module Controller
  
    # brings in the class-level methods form Solrize
    def self.included(base)
      base.extend Solrize
    end
  
    # sends a request to <SolrDocument>
    def solr_request(method_name, params={})
      SolrDocument.send method_name, params
    end
  
    # Solrize is a module that helps:
    #   - create basic action methods
    #   - setup params for a solr-base action
    #   - builds the response objects
    #   - creates useful helper methods which are exposed to the view
    module Solrize
    
      class Config
      
        attr_accessor :params, :captured_respond_to
      
        def initialize; @params={} end
      
        def respond_to(*args, &blk)
          self.captured_respond_to = {:args=>args, :blk=>blk}
        end
      
      end
    
      # BlockRequired -- a block is required when calling #solrize
      class BlockRequired < RuntimeError; end
    
      # solrize is the main class method that handles the magic
      # "action" -- a symbol or string that represent a controller action: :index
      # "finder_method" -- a class-level method on SolrDocument
      # "blk" -- a block to build solr params (evaluated in the controller instance)
      # 
      # If solrize is called like:
      #   solrize :index, :search {}
      # ...a blank #index action is built
      # a method called solr_index_params is created and exposed to the view
      #   - this helper method returns a hash that ends up being the result of the #solrize block
      # a method called solr_index_data is created (this calls SolrDocument) and called from a before_filter
      #   - this method sets 3 variables: @response, @documents and @document (the most common solr variables).
      # 
      # All of these methods are overridable AND the controller can still call #super.
      def solrize(action, finder_method, &blk)
      
        blk = lambda{|c|} if blk.nil?
      
        # create a dynamic module for setting up the action based methods
        action_mod = Module.new
        action_mod.class_eval <<-RUBY
        
          # add this method as an action
          def #{action}
            if captured = solr_#{action}_config.captured_respond_to
              send(:respond_to, *captured[:args], &captured[:blk])
            end
          end
        
          def solr_#{action}_config
            @solr_#{action}_config ||= Config.new
          end
        
          # this runs the block passed into the solrize call
          def solr_#{action}_params
            solrize_config = solr_#{action}_config
            @solr_#{action}_params ||= (
              self.instance_exec(solrize_config, &self.class.solr_#{action}_block)
              solrize_config.params
            )
          end
        
          # provides the data for the action and is called from a before_filter
          def solr_#{action}_data
            @response = solr_request(:#{finder_method}, solr_#{action}_params)
            @documents = @response.docs
            @document = @documents.first
          end
       
        RUBY
      
        # now include those methods:
        include action_mod
      
        # we need to setup another module for handling the block (blk)
        block_mod = Module.new
        # create an attribute for the block, named using the action name 
        block_mod.class_eval <<-RUBY
          attr_accessor :solr_#{action}_block
        RUBY
      
        # bring that method into the class: CatalogController.solr_index_block
        extend block_mod
      
        # now assign the block
        self.send("solr_#{action}_block=", blk)
      
        # set the params method as a helper
        helper_method "solr_#{action}_params"
      
        # setup the data method as before filter
        before_filter "solr_#{action}_data", :only=>action
      end
   
    end
  
  end
  
end