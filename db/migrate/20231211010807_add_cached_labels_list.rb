class AddCachedLabelsList < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :cached_label_list, :string
    Conversation.reset_column_information
    # acts-as-taggable-on 12.x uses CacheKeys; older versions use Cache
    cache_mod = ActsAsTaggableOn::Taggable.const_get(:CacheKeys) if ActsAsTaggableOn::Taggable.const_defined?(:CacheKeys)
    cache_mod ||= ActsAsTaggableOn::Taggable.const_get(:Cache) if ActsAsTaggableOn::Taggable.const_defined?(:Cache)
    cache_mod&.included(Conversation)
  end
end
