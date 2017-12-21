require_relative '../test_helper'

class MetadataTest < Minitest::Test

  def teardown
    Synthea::MODULES.clear
  end

  def test_validate_field_errors
    Synthea::MODULES['field_errors'] = JSON.parse(File.read(File.join(File.expand_path("../../fixtures/generic/validation/", __FILE__), 'field_errors.json')))
    context = Synthea::Generic::Context.new('field_errors')

    errors = validation_errors(context, 'Missing_Transition')
    assert_equal 1, errors.count, "Expected 1 error, got #{errors}"
    assert_starts_with('Required \'transition\' is missing', errors[0])

    errors = validation_errors(context, 'Guard_Missing_Allow')
    assert_equal 1, errors.count, "Expected 1 error, got #{errors}"
    assert_starts_with('Required \'allow\' is missing', errors[0])

    errors = validation_errors(context, 'Delay_Missing_Amount')
    assert_equal 1, errors.count, "Expected 1 error, got #{errors}"
    assert_starts_with('At least one of (range or exact) is required on', errors[0])

    errors = validation_errors(context, 'Encounter_Empty')
    assert_equal 1, errors.count, "Expected 1 error, got #{errors}"
    assert_starts_with('At least one of (wellness or (codes and encounter_class)) is required on', errors[0])

    errors = validation_errors(context, 'Encounter_With_Class_Missing_Codes')
    assert_equal 1, errors.count, "Expected 1 error, got #{errors}"
    assert_starts_with('At least one of (wellness or (codes and encounter_class)) is required on', errors[0])

    errors = validation_errors(context, 'Encounter_With_Code_Missing_System')
    assert_equal 1, errors.count, "Expected 1 error, got #{errors}"
    assert_starts_with('All of (code and system and display) are required on', errors[0])

    errors = validation_errors(context, 'Conditional_Transition_Missing_Transition')
    assert_equal 1, errors.count, "Expected 1 error, got #{errors}"
    assert_starts_with('Required \'transition\' is missing', errors[0])

    errors = validation_errors(context, 'Distributed_Transition_Missing_Pieces')
    assert_equal 2, errors.count, "Expected 2 errors, got #{errors}"
    assert_starts_with('All of (transition and distribution) are required on', errors[0])
    assert_starts_with('All of (transition and distribution) are required on', errors[1])

    errors = validation_errors(context, 'Complex_Transition_Missing_Pieces')
    assert_equal 1, errors.count, "Expected 1 error, got #{errors}"
    assert_starts_with('At least one of (transition or distributions) is required on', errors[0])

    errors = validation_errors(context, 'Date_Condition_Missing_Operator')
    assert_equal 1, errors.count, "Expected 1 error, got #{errors}"
    assert_starts_with('All of (year and operator) are required on', errors[0])
  end

  def test_validate_reference_errors
    skip "Unable to validate reference errors for submodules"
    Synthea::MODULES['reference_errors'] = JSON.parse(File.read(File.join(File.expand_path("../../fixtures/generic/validation/", __FILE__), 'reference_errors.json')))
    context = Synthea::Generic::Context.new('reference_errors')

    errors = context.validate
    assert_equal 3, errors.count, "Expected 3 errors, got #{errors}"
    assert_starts_with('target_encounter references state \'Nonexistent_State\' which does not exist', errors[0])
    assert_starts_with('condition_onset is expected to refer to a \'ConditionOnset\' but value \'Doctor_Visit\' is actually a \'Encounter\'', errors[1])
    assert_starts_with('State \'Unreachable_State\' is unreachable', errors[2])
  end

  def validation_errors(context, state_name)
    context.create_state(state_name).validate(context, [])
  end

  def assert_starts_with(prefix, obj, msg = nil)
    msg ||= "Expected '#{obj}' to start with '#{prefix}'"
    assert(obj.start_with?(prefix), msg)
  end

  def test_to_string
    obj = Class.new.extend(Synthea::Generic::Metadata)

    assert_equal 'symbol', obj.to_string(:symbol)
    assert_equal '(this or that)', obj.to_string(or: [:this, :that])
    assert_equal '(gold and silver)', obj.to_string(and: [:gold, :silver])
    assert_equal '((salt and pepper) or (sugar and spice))', obj.to_string( or: [{ and: [:salt, :pepper] }, { and: [:sugar, :spice] }])

    assert_raises (RuntimeError) { obj.to_string([:this, :that]) }
    assert_raises (RuntimeError) { obj.to_string('string') }
    assert_raises (RuntimeError) { obj.to_string({ or: [:this, :that], and: [:something_else] }) } # note this is 2 entries in 1 hash
    assert_raises (RuntimeError) { obj.to_string({}) }



  end
end
