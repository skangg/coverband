# frozen_string_literal: true

require File.expand_path('../../test_helper', File.dirname(__FILE__))

class HashRedisStoreTest < Minitest::Test
  def mock_file_hash; end

  def setup
    super
    @redis = Redis.new
    # FIXME: remove dependency on configuration and instead pass this in as an argument
    Coverband.configure do |config|
      config.root_paths = ['app_path/']
    end
    @store = Coverband::Adapters::HashRedisStore.new(@redis, redis_namespace: 'coverband_test')
    @store.clear!
    Coverband.configuration.store = @store
  end

  def mock_time(time = Time.now)
    Time.stubs(:now).returns(time)
    time
  end

  def test_no_coverage
    @store.save_report({})
    assert_equal({}, @store.coverage)
  end

  def test_coverage_for_file
    yesterday = DateTime.now.prev_day.to_time
    today = Time.now
    mock_time(yesterday)
    mock_file_hash
    @store.save_report(
      'app_path/dog.rb' => [0, 1, 2]
    )
    assert_equal(
      {
        'first_updated_at' => yesterday.to_i,
        'last_updated_at' => yesterday.to_i,
        'data' => [0, 1, 2]
      },
      @store.coverage['./dog.rb']
    )
    mock_time(today)
    @store.save_report(
      'app_path/dog.rb' => [1, 1, 0]
    )
    assert_equal(
      {
        'first_updated_at' => yesterday.to_i,
        'last_updated_at' => today.to_i,
        'data' => [1, 2, 2]
      },
      @store.coverage['./dog.rb']
    )
  end

  def test_ttl_set
    mock_file_hash
    @store = Coverband::Adapters::HashRedisStore.new(@redis, redis_namespace: 'coverband_test', ttl: 3600)
    @store.save_report(
      'app_path/dog.rb' => [0, 1, 2]
    )
    assert_operator(@redis.ttl('coverband_3_3.coverband_test.runtime../dog.rb'), :>, 0)
  end

  def test_no_ttl_set
    mock_file_hash
    @store = Coverband::Adapters::HashRedisStore.new(@redis, redis_namespace: 'coverband_test', ttl: nil)
    @store.save_report(
      'app_path/dog.rb' => [0, 1, 2]
    )
    assert_equal(@redis.ttl('coverband_3_3.coverband_test.runtime../dog.rb'), -1)
  end

  def test_coverage_for_multiple_files
    current_time = mock_time
    mock_file_hash
    data = {
      'app_path/dog.rb' => [0, nil, 1, 2],
      'app_path/cat.rb' => [1, 2, 0, 1, 5],
      'app_path/ferrit.rb' => [1, 5, nil, 2, nil]
    }
    @store.save_report(data)
    coverage = @store.coverage
    assert_equal(
      {
        'first_updated_at' => current_time.to_i,
        'last_updated_at' => current_time.to_i,
        'data' => [0, nil, 1, 2]
      }, @store.coverage['./dog.rb']
    )
    assert_equal [1, 2, 0, 1, 5], @store.coverage['./cat.rb']['data']
    assert_equal [1, 5, nil, 2, nil], @store.coverage['./ferrit.rb']['data']
  end

  def test_type
    mock_file_hash
    @store.type = :eager_loading
    data = {
      'app_path/dog.rb' => [0, nil, 1, 2]
    }
    @store.save_report(data)
    assert_equal 1, @store.coverage.length
    assert_equal [0, nil, 1, 2], @store.coverage['./dog.rb']['data']
    @store.type = Coverband::RUNTIME_TYPE
    data = {
      'app_path/cat.rb' => [1, 2, 0, 1, 5]
    }
    @store.save_report(data)
    assert_equal 1, @store.coverage.length
    assert_equal [1, 2, 0, 1, 5], @store.coverage['./cat.rb']['data']
  end

  def test_coverage_type
    mock_file_hash
    @store.type = :eager_loading
    data = {
      'app_path/dog.rb' => [0, nil, 1, 2]
    }
    @store.save_report(data)
    @store.type = Coverband::RUNTIME_TYPE
    assert_equal [0, nil, 1, 2], @store.coverage(:eager_loading)['./dog.rb']['data']
  end

  def test_clear
    mock_file_hash
    @store.type = Coverband::EAGER_TYPE
    data = {
      'app_path/dog.rb' => [0, nil, 1, 2]
    }
    @store.save_report(data)
    assert_equal 1, @store.coverage.length
    @store.type = Coverband::RUNTIME_TYPE
    data = {
      'app_path/cat.rb' => [1, 2, 0, 1, 5]
    }
    @store.save_report(data)
    assert_equal 1, @store.coverage.length
    @redis.set('random', 'data')
    @store.clear!
    @store.type = Coverband::RUNTIME_TYPE
    assert @store.coverage.empty?
    @store.type = :eager_loading
    assert @store.coverage.empty?
    assert_equal 'data', @redis.get('random')
  end

  def test_clear_file
    mock_file_hash
    @store.type = :eager_loading
    @store.save_report('app_path/dog.rb' => [0, 1, 1])
    @store.type = Coverband::RUNTIME_TYPE
    @store.save_report('app_path/dog.rb' => [1, 0, 1])
    assert_equal [1, 1, 2], @store.get_coverage_report[:merged]['./dog.rb']['data']
    @store.clear_file!('app_path/dog.rb')
    assert_nil @store.get_coverage_report[:merged]['./dog.rb']
  end
end
