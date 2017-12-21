require_relative '../test_helper'

class ExporterTest < Minitest::Test
  def setup
    Synthea::Config.exporter.years_of_history = 5
    Synthea::Config.exporter.location = './output/'

    @time = Time.now
    @patient = Synthea::Person.new
    @patient[:gender] = 'F'
    @patient.events.create(@time - 35.years, :birth, :birth)
    @patient[:age] = 35
    @patient[:city] = 'Bedford'
    @record = @patient.record_synthea
    @record.patient_info[:uuid] = '1234'
  end

  def test_export_filter_simple_cutoff
    @record.observation(:height, @time - 8.years, 64)
    @record.observation(:weight, @time - 4.years, 128)

    # observations should be filtered to the cutoff date

    filtered = Synthea::Output::Exporter.filter_for_export(@patient)

    assert_equal 1, filtered.record_synthea.observations.length
    assert_equal :weight, filtered.record_synthea.observations[0]['type']
    assert_equal @time - 4.years, filtered.record_synthea.observations[0]['time']
    assert_equal 128, filtered.record_synthea.observations[0]['value']
  end

  def test_export_filter_should_keep_old_active_medication
    @record.medication_start(:fakeitol, @time - 10.years, [:fake_reason])

    @record.medication_start(:placebitol, @time - 8.years, [:reason2])
    @record.medication_stop(:placebitol, @time - 6.years, :ineffective)

    filtered = Synthea::Output::Exporter.filter_for_export(@patient)

    assert_equal 1, filtered.record_synthea.medications.length
    assert_equal :fakeitol, filtered.record_synthea.medications[0]['type']
    assert_equal @time - 10.years, filtered.record_synthea.medications[0]['time']
  end

  def test_export_filter_should_keep_medication_that_ended_during_target
    @record.medication_start(:dimoxinil, @time - 10.years, [:baldness])
    @record.medication_stop(:dimoxinil, @time - 9.years, :snake_oil)

    @record.medication_start(:placebitol, @time - 8.years, [:reason2])
    @record.medication_stop(:placebitol, @time - 4.years, :ineffective)

    filtered = Synthea::Output::Exporter.filter_for_export(@patient)

    assert_equal 1, filtered.record_synthea.medications.length
    assert_equal :placebitol, filtered.record_synthea.medications[0]['type']
    assert_equal @time - 8.years, filtered.record_synthea.medications[0]['time']
    assert_equal @time - 4.years, filtered.record_synthea.medications[0]['stop']
  end

  def test_export_filter_should_keep_old_active_careplan
    @record.careplan_start(:stop_smoking, [:activity1], @time - 10.years, 'reasons' => [:smoking_is_bad_mkay])
    @record.careplan_stop(:stop_smoking, @time - 8.years)

    @record.careplan_start(:healthy_diet, [:eat_food_mostly_plants], @time - 12.years, 'reasons' => [:reason1])

    filtered = Synthea::Output::Exporter.filter_for_export(@patient)

    assert_equal 1, filtered.record_synthea.careplans.length
    assert_equal :healthy_diet, filtered.record_synthea.careplans[0]['type']
    assert_equal @time - 12.years, filtered.record_synthea.careplans[0]['time']
  end

  def test_export_filter_should_keep_careplan_that_ended_during_target
    @record.careplan_start(:stop_smoking, [:activity1], @time - 10.years, 'reasons' => [:smoking_is_bad_mkay])
    @record.careplan_stop(:stop_smoking, @time - 1.years)

    filtered = Synthea::Output::Exporter.filter_for_export(@patient)

    assert_equal 1, filtered.record_synthea.careplans.length
    assert_equal :stop_smoking, filtered.record_synthea.careplans[0]['type']
    assert_equal @time - 10.years, filtered.record_synthea.careplans[0]['time']
    assert_equal @time - 1.years, filtered.record_synthea.careplans[0]['stop']
  end

  def test_export_filter_should_keep_old_active_conditions
    @record.condition(:fakitis, @time - 10.years)
    @record.end_condition(:fakitis, @time - 8.years)

    @record.condition(:fakosis, @time - 10.years)

    filtered = Synthea::Output::Exporter.filter_for_export(@patient)

    assert_equal 1, filtered.record_synthea.conditions.length
    assert_equal :fakosis, filtered.record_synthea.conditions[0]['type']
    assert_equal @time - 10.years, filtered.record_synthea.conditions[0]['time']
  end

  def test_export_filter_should_keep_condition_that_ended_during_target
    @record.condition(:boneitis, @time - 10.years)
    @record.end_condition(:boneitis, @time - 2.years)

    @record.condition(:smallpox, @time - 10.years)
    @record.end_condition(:smallpox, @time - 9.years)

    filtered = Synthea::Output::Exporter.filter_for_export(@patient)

    assert_equal 1, filtered.record_synthea.conditions.length
    assert_equal :boneitis, filtered.record_synthea.conditions[0]['type']
    assert_equal @time - 10.years, filtered.record_synthea.conditions[0]['time']
  end

  def test_export_filter_should_keep_cause_of_death
    Synthea::Modules::Lifecycle.record_death(@patient, @time - 20.years, :rabies)

    filtered = Synthea::Output::Exporter.filter_for_export(@patient)

    assert_equal 1, filtered.record_synthea.encounters.length
    assert_equal :death_certification, filtered.record_synthea.encounters[0]['type']
    assert_equal @time - 20.years, filtered.record_synthea.encounters[0]['time']

    assert_equal 2, filtered.record_synthea.observations.length
    assert_equal :cause_of_death, filtered.record_synthea.observations[0]['type']
    assert_equal @time - 20.years, filtered.record_synthea.observations[0]['time']

    assert_equal :death_certificate, filtered.record_synthea.observations[1]['type']
    assert_equal @time - 20.years, filtered.record_synthea.observations[1]['time']
  end

  def test_export_filter_should_not_keep_old_stuff
    @record.procedure(:appendectomy, @time - 20.years, reason: :appendicitis)
    @record.encounter(:er_visit, @time - 18.years)
    @record.immunization(:flu_shot, @time - 12.years)
    @record.observation(:weight, @time - 10.years, 123)

    filtered = Synthea::Output::Exporter.filter_for_export(@patient)

    assert_empty filtered.record_synthea.procedures
    assert_empty filtered.record_synthea.encounters
    assert_empty filtered.record_synthea.immunizations
    assert_empty filtered.record_synthea.observations
  end

  def test_output_file_location_single_dir
    Synthea::Config.exporter.folder_per_city = false
    Synthea::Config.exporter.subfolders_by_id_substring = false

    assert_equal './output/fhir', Synthea::Output::Exporter.get_output_folder('fhir')
    assert_equal './output/fhir', Synthea::Output::Exporter.get_output_folder('fhir', @patient)
  end

  def test_output_file_location_cities_single
    Synthea::Config.exporter.folder_per_city = true
    Synthea::Config.exporter.subfolders_by_id_substring = false

    assert_equal './output/fhir', Synthea::Output::Exporter.get_output_folder('fhir')
    assert_equal './output/fhir/Bedford', Synthea::Output::Exporter.get_output_folder('fhir', @patient)
  end

  def test_output_file_location_single_split
    Synthea::Config.exporter.folder_per_city = false
    Synthea::Config.exporter.subfolders_by_id_substring = true

    assert_equal './output/fhir', Synthea::Output::Exporter.get_output_folder('fhir')
    assert_equal './output/fhir/12/123', Synthea::Output::Exporter.get_output_folder('fhir', @patient)
  end

  def test_output_file_location_cities_split
    Synthea::Config.exporter.folder_per_city = true
    Synthea::Config.exporter.subfolders_by_id_substring = true

    assert_equal './output/fhir', Synthea::Output::Exporter.get_output_folder('fhir')
    assert_equal './output/fhir/Bedford/12/123', Synthea::Output::Exporter.get_output_folder('fhir', @patient)
  end
end
