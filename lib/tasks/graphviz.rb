module Synthea
  module Tasks
    class Graphviz

      # color (true) or black & white (false)
      COLOR = true
      # setting styled to false will render bare nodes and edges
      # and also output a giant graph with all nodes and edges for all modules
      @@styled = true

      def self.generate_graphs
        folder = Synthea::Config.graphviz.output
        FileUtils.mkdir_p folder unless File.exists? folder

        puts "Rendering graphs to `#{folder}` folder..."
        @@count = 0

        image_files = []
        image_files << generateRulesBasedGraph
        image_files += generateWorkflowBasedGraphs

        @giant.output( :png => File.join(Synthea::Config.graphviz.output, 'giant.png') ) unless @@styled

        puts 'Writing index file...'
        index_file = File.join(folder, 'graphviz.html')
        f = File.open(index_file,'w:UTF-8')
        # f.write("<div id=\"links\">\n")
        image_files.each do |img|
          title = img[0..-5]
          f.write("<a href=\"graphviz/#{img}\" title=\"#{title}\">")
          # f.write("<img src=\"#{img}\" alt=\"#{title}\">")
          f.write("</a>\n")
        end
        # f.write("</div>\n")
        f.close
        puts 'Done.'
      end

      def self.next_id
        @@count += 1
        @@count.to_s
      end

      def self.generateRulesBasedGraph
        # Create a new graph
        @giant = GraphViz.new( :G, :type => :digraph )

        # Create the list of items
        items = []
        modules = {}
        Synthea::Rules.metadata.each do |key,rule|
          items << key
          items << rule[:inputs]
          items << rule[:outputs]
          modules[ rule[:module_name] ] = true
        end
        items = items.flatten.uniq

        # Choose a color for each module
        # available_colors = GraphViz::Utils::Colors::COLORS.keys
        available_colors = ['palevioletred','orange','lightgoldenrod','palegreen','lightblue','lavender','purple']
        modules.keys.each_with_index do |key,index|
          modules[key] = available_colors[index]
        end
        attribute_color = 'grey'

        # Create a node for each item
        nodes = {}
        if @@styled
          items.each{|i|nodes[i] = @giant.add_node(i.to_s)}
        else
          items.each do |i|
            if 'birth' == i.to_s
              label = 'Initial'
            elsif 'death' == i.to_s
              label = 'Terminal'
            else
              label = next_id
            end
            nodes[i] = @giant.add_node(label)
          end
        end

        # Make items that are not rules boxes
        components = nodes.keys - Synthea::Rules.metadata.keys
        components.each do |i|
          nodes[i]['shape']='Box'
          if COLOR
            nodes[i]['color']=attribute_color
            nodes[i]['style']='filled'
          end
        end if @@styled

        # Create the edges
        edges = []

        Synthea::Rules.metadata.each do |key,rule|
          node = nodes[key]
          if COLOR
            node['color'] = 'grey'
            node['color'] = modules[rule[:module_name]] if @@styled
            node['style'] = 'filled'
          end
          begin
            rule[:inputs].each do |input|
              other = nodes[input]
              if !edges.include?("#{input}:#{key}")
                @giant.add_edge( other, node)
                edges << "#{input}:#{key}"
              end
            end
            rule[:outputs].each do |output|
              other = nodes[output]
              if !edges.include?("#{key}:#{output}")
                @giant.add_edge( node, other)
                edges << "#{key}:#{output}"
              end
            end
          rescue Exception
            puts "There was an error rendering the rule #{key}"
          end
        end

        # Generate output image
        filename = 'synthea_rules.png'
        @giant.output( :png => File.join(Synthea::Config.graphviz.output, filename) )
        filename
      end

      def self.generateWorkflowBasedGraphs
        filenames = []
        module_dir = File.expand_path('../../generic/modules', __FILE__)
        graphviz_dir = Synthea::Config.graphviz.output

        # all modules and submodules
        Dir.glob(File.join(module_dir, '**', '*.json')) do |wf_file|
          filename = generate_workflow_based_graph(graphviz_dir, module_dir, wf_file)
          filenames << filename unless filename.nil?
        end
        filenames
      end

      def self.generate_workflow_based_graph(dir, module_dir, wf_file)
        # Create a new graph
        g = GraphViz.new( :G, :type => :digraph )
        wf = JSON.parse(File.read(wf_file))
        populate_graph(g, wf)
        populate_graph(@giant, wf) unless @@styled

        # Generate output image
        filename = "#{wf['name']}.png"
        export_path = File.join(dir, filename)

        is_submodule = submodule?(module_dir, wf_file)

        if is_submodule
          # For submodules, replicate the same directory structure as the modules directory.
          folder = submodule_folder(module_dir, wf_file)
          folder_path = File.join(dir, folder)
          # Create the submodule folder if it doesn't already exist
          FileUtils.mkdir_p folder_path unless File.exists? folder_path
          # Export the submodule into that folder
          export_path = File.join(folder_path, filename)
        end

        g.output( :png => export_path )
        # Only return the filenames of main modules
        filename unless is_submodule
      end

      def self.submodule?(module_dir, module_path)
        # Returns true if the module at module_path is a submodule.
        relative_path = module_path.split(module_dir + File::SEPARATOR)[1]
        relative_path && relative_path.include?(File::SEPARATOR)
      end

      def self.submodule_folder(module_dir, submodule_path)
        # Returns the relative path to a submodule folder.
        # e.g. "path/to/a/submodule.json" -> "path/to/a"
        relative_path = submodule_path.split(module_dir + File::SEPARATOR)[1]
        parts = relative_path.split(File::SEPARATOR)
        parts[0..(parts.length-2)].join(File::SEPARATOR)
      end

      def self.populate_graph(g, wf)
        # Create nodes based on states
        nodeMap = {}

        wf['states'].each do |name, state|
          if @@styled
            node = g.add_nodes(name, {'shape' => 'record', 'style' => 'rounded'})
          else
            label = name
            label = next_id unless ['Initial','Terminal'].include?(name)
            node = g.add_node(label)
          end

          if state['type'] == 'Initial' || state['type'] == 'Terminal'
            node['color'] = 'black'
            node['style'] = 'rounded,filled'
            node['fontcolor'] = 'white'
          end

          if @@styled
            details = state_description(state)
            if details.empty?
              node['label'] = (name == state['type']) ? name : "{ #{name} | #{state['type']} }"
            else
              node['label'] = "{ #{name} | { #{state['type']} | #{details} } }"
            end
          else
            node['color'] = 'grey'
            node['style'] = 'filled'
          end

          nodeMap[name] = node
        end

        # Create the edges based on the transitions
        wf['states'].each do |name, state|
          if state.has_key? 'direct_transition'
            begin
              g.add_edges( nodeMap[name], nodeMap[state['direct_transition']] )
            rescue
              raise "State '#{name}' is transitioning to an unknown state: '#{state['direct_transition']}'"
            end
          elsif state.has_key? 'distributed_transition'
            state['distributed_transition'].each do |t|
              distribution = t['distribution']
              if distribution.is_a?(Hash)
                # named attribute transition
                dist_label = "p(#{distribution['attribute']})"

                if distribution['default']
                  pct = distribution['default'] * 100
                  pct = pct.to_i if pct == pct.to_i
                  dist_label << ", default #{pct}%" 
                end
              else
                pct = distribution * 100
                pct = pct.to_i if pct == pct.to_i
                dist_label = "#{pct}%"
              end

              begin
                g.add_edges( nodeMap[name], nodeMap[t['transition']], label( dist_label ) )
              rescue
                raise "State '#{name}' is transitioning to an unknown state: '#{t['transition']}'"
              end
            end
          elsif state.has_key? 'conditional_transition'
            state['conditional_transition'].each_with_index do |t,i|
              cnd = t.has_key?('condition') ? logicDetails(t['condition']) : 'else'
              begin
                g.add_edges( nodeMap[name], nodeMap[t['transition']], label("#{i+1}. #{cnd}") )
              rescue
                raise "State '#{name}' is transitioning to an unknown state: '#{t['transition']}'"
              end
            end
          elsif state.has_key? 'complex_transition'
            transitions = Hash.new() { |hsh, key| hsh[key] = [] }

            state['complex_transition'].each do |t|
              cond = t.has_key?('condition') ? logicDetails(t['condition']) : 'else'
              if t['transition']
                nodes = [name, t['transition']]
                transitions[nodes] << "#{cond}"
              else
                t['distributions'].each do |dist|
                  pct = dist['distribution'] * 100
                  pct = pct.to_i if pct == pct.to_i
                  nodes = [name, dist['transition']]
                  transitions[nodes] << "#{cond}: #{pct}%"
                end
              end
            end

            transitions.each do |nodes, labels|
              begin
                g.add_edges( nodeMap[nodes[0]], nodeMap[nodes[1]], label(labels.join(',\n')) )
              rescue
                raise "State '#{nodes[0]}' is transitioning to an unknown state: '#{nodes[1]}'"
              end
            end
          end
        end
      end

      def self.label(message)
        if @@styled
          { 'label' => message }
        else
          {}
        end
      end

      def self.state_description(state)
        details = ''

        case state['type']
        when 'Guard'
          details = "Allow if " + logicDetails(state['allow'])
        when 'Delay', 'Death'
          if state.has_key? 'range'
            r = state['range']
            details = "#{r['low']} - #{r['high']} #{r['unit']}"
          elsif state.has_key? 'exact'
            e = state['exact']
            details = "#{e['quantity']} #{e['unit']}"
          end
        when 'Encounter'
          if state['wellness']
            details = 'Wait for regularly scheduled wellness encounter'
          end
        when 'EncounterEnd'
          details = 'End the current encounter'
          if state['discharge_disposition']
            code = state['discharge_disposition']
            details = details + "\\lDischarge Disposition: [#{code['code']}] #{code['display']}"
          end
        when 'SetAttribute'
          v = state['value']
          details = "Set '#{state['attribute']}' = #{v.nil? ? 'nil' : "'#{v}'"}"
        when 'Symptom'
          s = state['symptom']
          if state.has_key? 'range'
            r = state['range']
            details = "#{s}: #{r['low']} - #{r['high']}"
          elsif state.has_key? 'exact'
            e = state['exact']
            details = "#{s}: #{e['quantity']}"
          end
        when 'Observation'
          unit = state['unit']
          if unit
            unit = 'in ' + unit.gsub('{','(').gsub('}',')') # replace curly braces with parens, braces can cause issues
          end

          if state.has_key? 'vital_sign'
            details = "Record value from Vital Sign '#{state['vital_sign']}' #{unit}\\l"
          elsif state.has_key? 'attribute'
            details = "Record value from Attribute '#{state['attribute']}' #{unit}\\l"
          end
        when 'Counter'
          details = "#{state['action']} value of attribute '#{state['attribute']}' by 1"
        when 'VitalSign'
          vs = state['vital_sign']
          unit = state['unit']
          if state.has_key? 'range'
            r = state['range']
            details = "Set #{vs}: #{r['low']} - #{r['high']} #{unit}"
          elsif state.has_key? 'exact'
            e = state['exact']
            details = "Set #{vs}: #{e['quantity']} #{unit}"
          end
        when 'CallSubmodule'
          details = "Call submodule '#{state['submodule']}'"
        when 'MultiObservation', 'DiagnosticReport'
          details = "Group the last #{state['number_of_observations']} Observations\\l"
        end

        # Things common to many states
        if state.has_key? 'codes'
          state['codes'].each do |code|
            details = details + code['system'] + "[" + code['code'] + "]: " + code['display'] + "\\l"
          end
        end
        if state.has_key? 'target_encounter'
          verb = 'Perform'
          case state['type']
          when 'ConditionOnset', 'AllergyOnset'
            verb = 'Diagnose'
          when 'MedicationOrder'
            verb = 'Prescribe'
          end
          details = details + verb + " at " + state['target_encounter'] + "\\l"
        end
        if state.has_key? 'reason'
          details = details + "Reason: " + state['reason'] + "\\l"
        end
        if state.has_key? 'medication_order'
          details = details + "Prescribed at: #{state['medication_order']}\\l"
        end
        if state.has_key? 'condition_onset'
          details = details + "Onset at: #{state['condition_onset']}\\l"
        end
        if state.has_key? 'allergy_onset'
          details = details + "Onset at: #{state['allergy_onset']}\\l"
        end
        if state.has_key? 'careplan'
          details = details + "Prescribed at: #{state['careplan']}\\l"
        end
        if state.has_key? 'assign_to_attribute'
          details = details + "Assign to Attribute: '#{state['assign_to_attribute']}'\\l"
        end
        if state.has_key? 'referenced_by_attribute'
          details = details + "Referenced By Attribute: '#{state['referenced_by_attribute']}'\\l"
        end
        if state.has_key? 'activities'
          details = details + "\\lActivities:\\l"
          state['activities'].each do |activity|
            details = details + activity['system'] + "[" + activity['code'] + "]: " + activity['display'] + "\\l"
          end
        end
        if state.has_key? 'goals'
          details = details + "\\lGoals:\\l"
          state['goals'].each do |goal|
            if goal['text']
              details = details + goal['text'] + "\\l"
            elsif goal['codes']
              code = goal['codes'][0]
              details = details + code['system'] + "[" + code['code'] + "]: " + code['display'] + "\\l"
            elsif goal['observation']
              logic = goal['observation']
              obs = find_referenced_type(logic)
              details = details + "Observation #{obs} \\#{logic['operator']} #{logic['value']}\\l"
            end
          end
        end
        if state.has_key? 'duration'
          d = state['duration']
          details = details + "\\lDuration: #{d['low']} - #{d['high']} #{d['unit']}\\l"
        end
        if state.has_key? 'category'
          details = details + "Category: #{state['category']}\\l"
        end

        details
      end

      def self.logicDetails(logic)
        case logic['condition_type']
        when 'And', 'Or'
          subs = logic['conditions'].map do |c|
            if ['And','Or'].include?(c['condition_type'])
              "(\\l" + logicDetails(c) + ")\\l"
            else
              logicDetails(c)
            end
          end
          subs.join(logic['condition_type'].downcase + ' ')
        when 'At Least', 'At Most'
          threshold = logic['minimum'] || logic['maximum']
          subs = logic['conditions'].map do |c|
            if ['And','Or'].include?(c['condition_type'])
              "(\\l" + logicDetails(c) + ")\\l"
            else
              logicDetails(c)
            end
          end
          "#{logic['condition_type']} #{threshold} of:\\l- #{subs.join('- ')}"
        when 'Not'
          c = logic['condition']
          if ['And','Or'].include?(c['condition_type'])
            "not (\\l" + logicDetails(c) + ")\\l"
          else
            "not " + logicDetails(c)
          end
        when 'Gender'
          "gender is '#{logic['gender']}'\\l"
        when 'Age'
          "age \\#{logic['operator']} #{logic['quantity']} #{logic['unit']}\\l"
        when 'Socioeconomic Status'
          "#{logic['category']} Socioeconomic Status\\l"
        when 'Race'
          "race is '#{logic['race']}'\\l"
        when 'Date'
          "Year is \\#{logic['operator']} #{logic['year']}\\l"
        when 'Symptom'
          "Symptom: '#{logic['symptom']}' \\#{logic['operator']} #{logic['value']}\\l"
        when 'PriorState'
          within = logic['within']
          if within
            "state '#{logic['name']}' has been processed within #{within['quantity']} #{within['unit']}\\l"
          else
            "state '#{logic['name']}' has been processed\\l"
          end
        when 'Attribute'
          "Attribute: '#{logic['attribute']}' \\#{logic['operator']} #{logic['value']}\\l"
        when 'Observation'
          obs = find_referenced_type(logic)
          "Observation #{obs} \\#{logic['operator']} #{logic['value']}\\l"
        when 'Vital Sign'
          "Vital Sign #{logic['vital_sign']} \\#{logic['operator']} #{logic['value']}\\l"
        when 'Active Condition'
          cond = find_referenced_type(logic)
          "Condition #{cond} is active\\l"
        when 'Active CarePlan'
          plan = find_referenced_type(logic)
          "CarePlan #{plan} is active\\l"
        when 'Active Medication'
          med = find_referenced_type(logic)
          "Medication #{med} is active\\l"
        when 'Active Allergy'
          alg = find_referenced_type(logic)
          "Allergy #{alg} is active\\l"
        when 'True', 'False'
          logic['condition_type']
        else
          raise "Unsupported Condition: #{logic['condition_type']}"
        end
      end

      def self.find_referenced_type(logic)
        if logic['codes']
          code = logic['codes'].first
          "'#{code['system']} [#{code['code']}]: #{code['display']}'"
        elsif logic['referenced_by_attribute']
          "Referenced By Attribute: '#{logic['referenced_by_attribute']}'"
        else
          raise "#{logic['condition_type']} condition must be specified by code or attribute"
        end
      end
    end
  end
end
