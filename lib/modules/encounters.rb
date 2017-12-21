module Synthea
  module Modules
    class Encounters < Synthea::Rules
      # People have encounters
      rule :schedule_encounter, [:age], [:encounter] do |time, entity|
        if entity.alive?(time)
          unprocessed_events = entity.events.unprocessed_before(time, :encounter_ordered)
          unprocessed_events.each do |event|
            entity.events.process(event)

            schedule_variance = Synthea::Config.schedule.variance
            birthdate = entity.event(:birth).time
            deathdate = entity.event(:death).try(:time)

            age_in_years = entity[:age]
            if age_in_years >= 3
              delta = if age_in_years <= 19
                        1.year
                      elsif age_in_years <= 39
                        3.years
                      elsif age_in_years <= 49
                        2.years
                      else
                        1.year
                      end
            else
              age_in_months = Synthea::Modules::Lifecycle.age(time, birthdate, deathdate, :months)
              delta = if age_in_months <= 1
                        1.months
                      elsif age_in_months <= 5
                        2.months
                      elsif age_in_months <= 17
                        3.months
                      else
                        6.months
                      end
            end
            next_date = time + Distribution::Normal.rng(delta * 1.0, delta * schedule_variance).call
            entity.events.create(next_date, :encounter, :schedule_encounter)
          end
        end
      end

      rule :encounter, [], [:schedule_encounter, :observations, :lab_results, :diagnoses, :immunizations] do |time, entity|
        if entity.alive?(time)
          # find closest service provider
          provider = Synthea::Provider.find_closest_service(entity, 'ambulatory')
          # hash below is added as reference
          entity.add_current_provider('ruby_module_encounter_' + time.to_s, provider)

          unprocessed_events = entity.events.unprocessed_before(time, :encounter)
          unprocessed_events.each do |event|
            entity.events.process(event)
            self.class.encounter(entity, event.time)
            Synthea::Modules::Immunizations.perform_encounter(entity, event.time)
            Synthea::Modules::CardiovascularDisease.perform_encounter(entity, event.time)
            Synthea::Modules::Generic.perform_wellness_encounter(entity, event.time)
            # Schedule the next general encounter unless this one was driven by symptoms
            unless event.rule == :symptoms_cause_encounter
              entity.events.create(event.time, :encounter_ordered, :encounter)
            end
          end
          # reset current provider hash
          entity.remove_current_provider('ruby_module_encounter_' + time.to_s)
        end
      end

      # Sometimes people schedule encounters because they're experiencing symptoms
      rule :symptoms_cause_encounter, [:symptoms, :tracked_symptoms], [:encounter, :symptoms_cause_encounter] do |time, entity|
        if entity.alive?(time)
          unprocessed_events = entity.events.unprocessed_before(time, :symptoms_cause_encounter)
          unprocessed_events.each do |event|
            entity.events.process(event)

            # We want a patient to perform a self assessment on whether symptoms are severe enough to make an
            # appointment on a regular basis, currently we pick monthly
            entity.events.create(time + 1.month, :symptoms_cause_encounter, :symptoms_cause_encounter)

            # Check for severe symptoms
            severe_symptoms = entity.get_symptoms_exceeding(85)
            next if severe_symptoms.empty?

            # A patient won't always make an apointment
            next unless rand < 0.1

            # We don't want a patient to schedule more than one; keep track of whether a patient has already
            # paid attention to a symptom; at the moment this is symplistic, a patient will only ever schedule
            # a single apointment for a particular symptom across all time
            next if (severe_symptoms - (entity[:tracked_symptoms] || [])).blank?
            entity[:tracked_symptoms] ||= []
            entity[:tracked_symptoms] |= severe_symptoms

            # The patient has decided to see the doctor, and schedules an apointent for 1-4 weeks in future
            entity.events.create(time + rand(1..4).weeks, :encounter, :symptoms_cause_encounter)
          end
        end
      end

      # processes all emergency events. Implemented as a function instead of a rule because emergency events must be procesed
      # immediately rather than waiting til the next time period. Patient may die, resulting in rule not being called.
      def self.emergency_visit(time, entity)
        unprocessed_events = entity.events.unprocessed_before(time, :emergency_encounter)
        unprocessed_events.each do |event|
          entity.events.process(event)
          emergency_encounter(entity, time)
        end

        unprocessed_events = entity.events.unprocessed.select { |x| [:myocardial_infarction, :cardiac_arrest, :stroke].include?(x.type) && x.time <= time }
        unprocessed_events.each do |event|
          entity.events.process(event)
          Synthea::Modules::CardiovascularDisease.perform_emergency(entity, event)
        end
        # reset current provider hash
        entity.remove_current_provider('cardiovascular_emergency')
      end

      #------------------------------------------------------------------------------------------#

      def self.encounter(entity, time, reason = nil)
        age = entity[:age]
        type = if age <= 1
                 :age_lt_1
               elsif age <= 4
                 :age_lt_4
               elsif age <= 11
                 :age_lt_11
               elsif age <= 17
                 :age_lt_17
               elsif age <= 39
                 :age_lt_39
               elsif age <= 64
                 :age_lt_64
               else
                 :age_senior
               end

        # find closest service provider
        encounter_data = ENCOUNTER_LOOKUP[type]
        service = encounter_data[:class]
        provider = Synthea::Provider.find_closest_service(entity, service)
        # hash below is added as reference
        entity.add_current_provider('ruby_module_encounter_' + time.to_s, provider)
        provider.increment_encounters

        options = { reason: reason, provider: entity.ambulatory_provider }
        entity.record_synthea.encounter(type, time, options)
        # TODO: wellness encounters need their duration defined by the activities performed
        # the trouble is those activities are split among many modules
        entity.record_synthea.encounter_end(type, time + 1.hour)
      end

      def self.emergency_encounter(entity, time, reason = nil)
        # find closest service provider with emergency service
        provider = Synthea::Provider.find_closest_service(entity, 'emergency')
        # hash below is added as reference
        entity.add_current_provider('cardiovascular_emergency', provider)
        provider.increment_encounters

        options = { reason: reason, provider: provider }
        entity.record_synthea.encounter(:emergency, time, options)
        # TODO: emergency encounters need their duration to be defined by the activities performed
        # based on the emergencies given here (heart attack, stroke)
        # assume people will be in the hospital for observation for a few days
        entity.record_synthea.encounter_end(:emergency, time + 4.days)
      end
    end
  end
end
