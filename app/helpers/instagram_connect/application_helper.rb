module InstagramConnect
  module ApplicationHelper
    # Emits a <style> block: the theme values from config as CSS variables,
    # followed by the gem's base stylesheet. Included automatically in the gem's
    # own layout; a host inheriting its own layout can drop this into its <head>.
    def instagram_connect_styles
      vars = InstagramConnect.configuration.resolved_theme.map do |key, value|
        "--ic-#{key.to_s.tr('_', '-')}: #{value};"
      end.join(" ")

      content_tag(:style, ":root { #{vars} }\n#{InstagramConnect.base_css}".html_safe)
    end
  end
end
