module Typhoeus
  USER_AGENT = "Typhoeus - http://github.com/pauldix/typhoeus/tree/master"
  
  def self.included(base)
    base.extend ClassMethods
  end
    
  module ClassMethods
    def get(url, options = {})
      remote_proxy_object(url, :get, options)
    end
    
    def post(url, options = {}, &block)
      remote_proxy_object(url, :post, options)
    end

    def put(url, options = {}, &block)
      remote_proxy_object(url, :put, options)
    end
    
    def delete(url, options = {}, &block)
      remote_proxy_object(url, :delete, options)
    end
    
    def remote_proxy_object(url, method, options)
      easy = Typhoeus.get_easy_object
      
      easy.url                   = url
      easy.method                = method
      easy.headers["User-Agent"] = (options[:user_agent] || Typhoeus::USER_AGENT)
      easy.params                = options[:params] if options[:params]
      easy.request_body          = options[:body] if options[:body]
      easy.timeout               = options[:timeout] if options[:timeout]
      
      easy
      
      proxy = Typhoeus::RemoteProxyObject.new(clear_memoized_proxy_objects, easy, options)
      set_memoized_proxy_object(method, url, options, proxy)
    end
    
    def remote_defaults(options)
      @remote_defaults = options
    end
    
    def call_remote_method(method_name, args)
      m = @remote_methods[method_name]
      
      base_uri = args.delete(:base_uri) || m.base_uri || ""

      if args.has_key? :path
        path = args.delete(:path)
      else
        path = m.interpolate_path_with_arguments(args)
      end
      path ||= ""
      
      http_method = m.http_method
      url         = base_uri + path
      options     = m.merge_options(args)
      
      # proxy_object = memoized_proxy_object(http_method, url, options)
      # return proxy_object unless proxy_object.nil?
      # 
      # if m.cache_responses?
      #   object = @cache.get(get_memcache_response_key(method_name, args))
      #   if object
      #     set_memoized_proxy_object(http_method, url, options, object)
      #     return object
      #   end
      # end
      
      proxy = memoized_proxy_object(http_method, url, options)
      unless proxy
        if m.cache_responses?
          options[:cache] = @cache
          options[:cache_key] = get_memcache_response_key(method_name, args)
          options[:cache_timeout] = m.cache_ttl
        end
        proxy = send(http_method, url, options)
      end
      proxy
    end
    
    def set_memoized_proxy_object(http_method, url, options, object)
      @memoized_proxy_objects ||= {}
      @memoized_proxy_objects["#{http_method}_#{url}_#{options.to_s}"] = object
    end
    
    def memoized_proxy_object(http_method, url, options)
      @memoized_proxy_objects ||= {}
      @memoized_proxy_objects["#{http_method}_#{url}_#{options.to_s}"]
    end
    
    def clear_memoized_proxy_objects
      lambda { @memoized_proxy_objects = {} }
    end

    def get_memcache_response_key(remote_method_name, args)
      result = "#{remote_method_name.to_s}-#{args.to_s}"
      (Digest::SHA2.new << result).to_s
    end
    
    def cache=(cache)
      @cache = cache
    end
    
    def define_remote_method(name, args = {})
      @remote_defaults  ||= {}
      args[:method]     ||= @remote_defaults[:method]
      args[:on_success] ||= @remote_defaults[:on_success]
      args[:on_failure] ||= @remote_defaults[:on_failure]
      args[:base_uri]   ||= @remote_defaults[:base_uri]
      args[:path]       ||= @remote_defaults[:path]
      m = RemoteMethod.new(args)

      @remote_methods ||= {}
      @remote_methods[name] = m

      class_eval <<-SRC
        def self.#{name.to_s}(args = {})
          call_remote_method(:#{name.to_s}, args)
        end
      SRC
    end
  end # ClassMethods
end