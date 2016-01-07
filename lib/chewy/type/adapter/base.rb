module Chewy
  class Type
    module Adapter
      # Basic adapter class. Contains interface, need to implement to add any classes support
      class Base
        BATCH_SIZE = 1000

        attr_reader :target, :options

        # Returns `true` if this adapter is applicable for the given target.
        #
        def self.accepts?(target)
          true
        end

        # Camelcased name, used as type class constant name.
        # For returned value 'Product' will be generated class name `ProductsIndex::Product`
        #
        def name
          fail NotImplementedError
        end

        # Underscored type name, user for elasticsearch type creation
        # and for type class access with ProductsIndex.type_hash hash or method.
        # `ProductsIndex.type_hash['product']` or `ProductsIndex.product`
        #
        def type_name
          @type_name ||= name.underscore
        end

        # Returns shortest identifies for further postponed importing.
        # For ORM/ODM it will be an array of ids for simple objects -
        # just objects themselves
        #
        def identify(collection)
          fail NotImplementedError
        end

        # Splits passed objects to groups according to `:batch_size` options.
        # For every group crates hash with action keys. Example:
        #
        #   { delete: [object1, object2], index: [object3, object4, object5] }
        #
        # Returns true id all the block call returns true and false otherwise
        #
        def import(*args, &block)
          fail NotImplementedError
        end

        # Returns array of loaded objects for passed objects array. If some object
        # was not loaded, it returns `nil` in the place of this object
        #
        #   load(double(id: 1), double(id: 2), double(id: 3)) #=>
        #     # [<Product id: 1>, nil, <Product id: 3>], assuming, #2 was not found
        #
        def load(*args)
          fail NotImplementedError
        end

        private

        def grouped_objects(objects)
          objects.to_a.group_by do |object|
            delete_from_index?(object) ? :delete : :index
          end
        end

        def delete_from_index?(object)
          delete_if = options[:delete_if]
          delete ||= case delete_if
                     when Symbol, String
                       object.send delete_if
                     when Proc
                       delete_if.arity == 1 ? delete_if.call(object) : object.instance_exec(&delete_if)
          end

          !!delete
        end
      end
    end
  end
end
