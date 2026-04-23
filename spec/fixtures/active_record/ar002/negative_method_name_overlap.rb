# frozen_string_literal: true

# Negative fixture: method names that overlap but are not the bypass methods
class ReportService
  def update_column_widths(widths)
    @columns.each_with_index do |col, i|
      col.width = widths[i]
    end
  end

  def update_all_reports
    reports.each { |r| r.update(status: "refreshed") }
  end
end
