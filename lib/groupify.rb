require 'active_support'

module Groupify
  mattr_accessor :group_membership_class_name,
                 :group_class_name

  self.group_class_name = 'Group'
  self.group_membership_class_name = 'GroupMembership'

  def self.configure
    yield self
  end
end

require 'groupify/railtie' if defined?(Rails)
