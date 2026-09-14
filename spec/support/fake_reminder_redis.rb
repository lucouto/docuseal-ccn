# frozen_string_literal: true

# CCN fork — Stage 4, US1: CI has no Redis service (only Postgres — .github/workflows/ci.yml), so
# Ccn::Reminders's lock is exercised against this tiny double instead of a live connection. The double
# implements exactly the two calls lib/ccn/reminders.rb makes on Sidekiq.redis: an NX/EX SET and the
# compare-and-delete EVAL script.
class FakeReminderRedis
  def initialize
    @store = {}
  end

  def set(key, value, nx:, ex:)
    return false if nx && @store.key?(key)

    @store[key] = value
    true
  end

  def call(_command, _script, _numkeys, key, value)
    if @store[key] == value
      @store.delete(key)
      1
    else
      0
    end
  end
end
