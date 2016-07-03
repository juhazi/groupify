module Groupify
  module ActiveRecord

    # Usage:
    #    class User < ActiveRecord::Base
    #        groupify :group_member
    #        ...
    #    end
    #
    #    user.groups << group
    #
    module GroupMember
      extend ActiveSupport::Concern

      included do
        unless respond_to?(:group_memberships_as_member)
          has_many :group_memberships_as_member,
                   as: :member,
                   autosave: true,
                   dependent: :destroy,
                   class_name: Groupify.group_membership_class_name
        end

        if ActiveSupport::VERSION::MAJOR > 3
          has_many :groups, ->{ uniq },
                   through: :group_memberships_as_member,
                   as: :group,
                   source_type: @group_class_name,
                   extend: GroupAssociationExtensions
        else
          has_many :groups,
                   uniq: true,
                   through: :group_memberships_as_member,
                   as: :group,
                   source_type: @group_class_name,
                   extend: GroupAssociationExtensions
        end
      end

      module GroupAssociationExtensions
        def as(membership_type)
          return self unless membership_type
          where(group_memberships: {membership_type: membership_type})
        end

        def delete(*args)
          opts = args.extract_options!
          groups = args.flatten

          if opts[:as]
            proxy_association.owner.group_memberships_as_member.where(group_id: groups.map(&:id)).as(opts[:as]).delete_all
          else
            super(*groups)
          end
        end

        def destroy(*args)
          opts = args.extract_options!
          groups = args.flatten

          if opts[:as]
            proxy_association.owner.group_memberships_as_member.where(group_id: groups.map(&:id)).as(opts[:as]).destroy_all
          else
            super(*groups)
          end
        end
      end

      def in_group?(group, opts={})
        criteria = {group_id: group.id}

        if opts[:as]
          criteria.merge!(membership_type: opts[:as])
        end

        group_memberships_as_member.exists?(criteria)
      end

      def in_any_group?(*args)
        opts = args.extract_options!
        groups = args

        groups.flatten.each do |group|
          return true if in_group?(group, opts)
        end
        return false
      end

      def in_all_groups?(*args)
        opts = args.extract_options!
        groups = args.flatten

        groups.to_set.subset? self.groups.as(opts[:as]).to_set
      end

      def in_only_groups?(*args)
        opts = args.extract_options!
        groups = args.flatten

        groups.to_set == self.groups.as(opts[:as]).to_set
      end

      def shares_any_group?(other, opts={})
        in_any_group?(other.groups, opts)
      end

      module ClassMethods
        def as(membership_type)
          joins(:group_memberships_as_member).where(group_memberships: { membership_type: membership_type })
        end

        def in_group(group)
          return none unless group.present?

          joins(:group_memberships_as_member).where(group_memberships: { group_id: group.id }).uniq
        end

        def in_any_group(*groups)
          groups = groups.flatten
          return none unless groups.present?

          joins(:group_memberships_as_member).where(group_memberships: { group_id: groups.map(&:id) }).uniq
        end

        def in_all_groups(*groups)
          groups = groups.flatten
          return none unless groups.present?

          joins(:group_memberships_as_member).
              group("#{quoted_table_name}.#{connection.quote_column_name('id')}").
              where(group_memberships: {group_id: groups.map(&:id)}).
              having("COUNT(#{reflect_on_association(:group_memberships_as_member).klass.quoted_table_name}.#{connection.quote_column_name('group_id')}) = ?", groups.count).
              uniq
        end

        def in_only_groups(*groups)
          groups = groups.flatten
          return none unless groups.present?

          joins(:group_memberships_as_member).
              group("#{quoted_table_name}.#{connection.quote_column_name('id')}").
              having("COUNT(DISTINCT #{reflect_on_association(:group_memberships_as_member).klass.quoted_table_name}.#{connection.quote_column_name('group_id')}) = ?", groups.count).
              uniq
        end

        def shares_any_group(other)
          in_any_group(other.groups)
        end

        # Define which group subclasses can have this class as a member
        def has_groups(*names)
          Array.wrap(names.flatten).each do |name|
            klass = name.to_s.classify.constantize
            register_group(klass)
          end
        end

        protected

        def register_group(group_klass)
          (@group_klasses ||= Set.new) << group_klass

          define_group_association group_klass

          group_klass
        end

        def define_group_association(group_klass)
          association_name = group_klass.model_name.plural.to_sym

          has_many association_name, *group_association_options(group_klass)

          define_method(association_name) do |*args|
            opts = args.extract_options!
            membership_type = opts[:as]
            if membership_type.present?
              super().as(membership_type)
            else
              super()
            end
          end
        end

        def group_association_options(group_klass)
          source_type = group_klass.base_class

          base_options = {
            through: :group_memberships_as_member,
            as: :group,
            source: :group,
            source_type: source_type,
            extend: GroupAssociationExtensions
          }

          if ActiveSupport::VERSION::MAJOR > 3
            filter = -> { uniq.where("#{group_klass.table_name}.type = ?", group_klass.name.to_s) }
            [
              filter,
              base_options
            ]
          else
            options = base_options.merge(uniq: true)
            options.merge!(conditions: ["#{group_klass.table_name}.type = ?", group_klass.name.to_s])
            [options]
          end
        end
      end
    end
  end
end
