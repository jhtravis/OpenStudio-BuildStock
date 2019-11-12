# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# insert your copyright here

resources_path = File.absolute_path(File.join(File.dirname(__FILE__), "../HPXMLtoOpenStudio/resources"))
unless File.exists? resources_path
  resources_path = File.join(OpenStudio::BCLMeasure::userMeasuresDir.to_s, "HPXMLtoOpenStudio/resources") # Hack to run measures in the OS App since applied measures are copied off into a temporary directory
end

require File.join(resources_path, "constants")
require File.join(resources_path, "geometry")
require File.join(resources_path, "unit_conversions")
require File.join(resources_path, "schedules")

# start the measure
class CreateResidentialMultifamilyGeometry < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'CreateResidentialMultifamilyGeometry'
  end

  # human readable description
  def description
    return "Sets the geometry for a single unit in a multifamily building based on the user-specified location of the unit. Sets the number of bedrooms, bathrooms, and occupants in the unit.#{Constants.WorkflowDescription}"
  end

  # human readable description of modeling approach
  def modeler_description
    return "Creates multifamily geometry for a single unit. Also, sets (or replaces) BuildingUnit objects that store the number of bedrooms and bathrooms associated with the model. Sets (or replaces) the People object for each finished space in the model."
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument for unit living space floor area
    unit_ffa = OpenStudio::Measure::OSArgument::makeDoubleArgument("unit_ffa", true)
    unit_ffa.setDisplayName("Unit Finished Floor Area")
    unit_ffa.setUnits("ft^2")
    unit_ffa.setDescription("Unit floor area of the finished space (including any finished basement floor area).")
    unit_ffa.setDefaultValue(900.0)
    args << unit_ffa

    # make an argument for living space height
    wall_height = OpenStudio::Measure::OSArgument::makeDoubleArgument("wall_height", true)
    wall_height.setDisplayName("Wall Height (Per Floor)")
    wall_height.setUnits("ft")
    wall_height.setDescription("The height of the living space walls.")
    wall_height.setDefaultValue(8.0)
    args << wall_height

    # make an argument for total number of floors
    num_floors = OpenStudio::Measure::OSArgument::makeIntegerArgument("num_floors", true)
    num_floors.setDisplayName("Building Number of Floors")
    num_floors.setUnits("#")
    num_floors.setDescription("The number of floors above grade.")
    num_floors.setDefaultValue(1)
    args << num_floors

    # make an argument for number of units
    num_units = OpenStudio::Measure::OSArgument::makeIntegerArgument("num_units", true)
    num_units.setDisplayName("Num Units")
    num_units.setUnits("#")
    num_units.setDescription("The number of units. This must be divisible by the number of floors.")
    num_units.setDefaultValue(2)
    args << num_units

    # make an argument for unit aspect ratio
    unit_aspect_ratio = OpenStudio::Measure::OSArgument::makeDoubleArgument("unit_aspect_ratio", true)
    unit_aspect_ratio.setDisplayName("Unit Aspect Ratio")
    unit_aspect_ratio.setUnits("FB/LR")
    unit_aspect_ratio.setDescription("The ratio of the front/back wall length to the left/right wall length.")
    unit_aspect_ratio.setDefaultValue(2.0)
    args << unit_aspect_ratio

    # make an argument for corridor position
    corridor_position_display_names = OpenStudio::StringVector.new
    corridor_position_display_names << "Double-Loaded Interior"
    corridor_position_display_names << "Single Exterior (Front)"
    corridor_position_display_names << "Double Exterior"
    corridor_position_display_names << "None"

    corridor_position = OpenStudio::Measure::OSArgument::makeChoiceArgument("corridor_position", corridor_position_display_names, true)
    corridor_position.setDisplayName("Corridor Position")
    corridor_position.setDescription("The position of the corridor.")
    corridor_position.setDefaultValue("Double-Loaded Interior")
    args << corridor_position

    # make an argument for corridor width
    corridor_width = OpenStudio::Measure::OSArgument::makeDoubleArgument("corridor_width", true)
    corridor_width.setDisplayName("Corridor Width")
    corridor_width.setUnits("ft")
    corridor_width.setDescription("The width of the corridor.")
    corridor_width.setDefaultValue(10.0)
    args << corridor_width

    # make an argument for inset width
    inset_width = OpenStudio::Measure::OSArgument::makeDoubleArgument("inset_width", true)
    inset_width.setDisplayName("Inset Width")
    inset_width.setUnits("ft")
    inset_width.setDescription("The width of the inset.")
    inset_width.setDefaultValue(0.0)
    args << inset_width

    # make an argument for inset depth
    inset_depth = OpenStudio::Measure::OSArgument::makeDoubleArgument("inset_depth", true)
    inset_depth.setDisplayName("Inset Depth")
    inset_depth.setUnits("ft")
    inset_depth.setDescription("The depth of the inset.")
    inset_depth.setDefaultValue(0.0)
    args << inset_depth

    # make an argument for inset position
    inset_position_display_names = OpenStudio::StringVector.new
    inset_position_display_names << "Right"
    inset_position_display_names << "Left"

    inset_position = OpenStudio::Measure::OSArgument::makeChoiceArgument("inset_position", inset_position_display_names, true)
    inset_position.setDisplayName("Inset Position")
    inset_position.setDescription("The position of the inset.")
    inset_position.setDefaultValue("Right")
    args << inset_position

    # make an argument for balcony depth
    balcony_depth = OpenStudio::Measure::OSArgument::makeDoubleArgument("balcony_depth", true)
    balcony_depth.setDisplayName("Balcony Depth")
    balcony_depth.setUnits("ft")
    balcony_depth.setDescription("The depth of the balcony.")
    balcony_depth.setDefaultValue(0.0)
    args << balcony_depth

    # make a choice argument for model objects
    foundation_display_names = OpenStudio::StringVector.new
    foundation_display_names << "slab"
    foundation_display_names << "crawlspace"
    foundation_display_names << "unfinished basement"

    # make a choice argument for foundation type
    foundation_type = OpenStudio::Measure::OSArgument::makeChoiceArgument("foundation_type", foundation_display_names, true)
    foundation_type.setDisplayName("Foundation Type")
    foundation_type.setDescription("The foundation type of the building.")
    foundation_type.setDefaultValue("slab")
    args << foundation_type

    # make an argument for crawlspace height
    foundation_height = OpenStudio::Measure::OSArgument::makeDoubleArgument("foundation_height", true)
    foundation_height.setDisplayName("Foundation Height")
    foundation_height.setUnits("ft")
    foundation_height.setDescription("The height of the foundation (e.g., 3ft for crawlspace, 8ft for basement).")
    foundation_height.setDefaultValue(3.0)
    args << foundation_height

    # make a choice argument for eaves depth
    eaves_depth = OpenStudio::Measure::OSArgument::makeDoubleArgument("eaves_depth", true)
    eaves_depth.setDisplayName("Eaves Depth")
    eaves_depth.setUnits("ft")
    eaves_depth.setDescription("The eaves depth of the roof.")
    eaves_depth.setDefaultValue(2.0)
    args << eaves_depth

    # make a string argument for number of bedrooms
    num_br = OpenStudio::Measure::OSArgument::makeStringArgument("num_bedrooms", true)
    num_br.setDisplayName("Number of Bedrooms")
    num_br.setDescription("Specify the number of bedrooms. Used to determine the energy usage of appliances and plug loads, hot water usage, mechanical ventilation rate, etc.")
    num_br.setDefaultValue("3")
    args << num_br

    # make a string argument for number of bathrooms
    num_ba = OpenStudio::Measure::OSArgument::makeStringArgument("num_bathrooms", true)
    num_ba.setDisplayName("Number of Bathrooms")
    num_ba.setDescription("Specify the number of bathrooms. Used to determine the hot water usage, etc.")
    num_ba.setDefaultValue("2")
    args << num_ba

    # Make a string argument for occupants (auto or number)
    num_occupants = OpenStudio::Measure::OSArgument::makeStringArgument("num_occupants", true)
    num_occupants.setDisplayName("Number of Occupants")
    num_occupants.setDescription("Specify the number of occupants. A value of '#{Constants.Auto}' will calculate the average number of occupants from the number of bedrooms. Used to specify the internal gains from people only.")
    num_occupants.setDefaultValue(Constants.Auto)
    args << num_occupants

    # Make a string argument for 24 weekday schedule values
    occupants_weekday_sch = OpenStudio::Measure::OSArgument::makeStringArgument("occupants_weekday_sch", true)
    occupants_weekday_sch.setDisplayName("Occupants Weekday schedule")
    occupants_weekday_sch.setDescription("Specify the 24-hour weekday schedule.")
    occupants_weekday_sch.setDefaultValue("1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 0.88, 0.41, 0.24, 0.24, 0.24, 0.24, 0.24, 0.24, 0.24, 0.29, 0.55, 0.90, 0.90, 0.90, 1.00, 1.00, 1.00")
    args << occupants_weekday_sch

    # Make a string argument for 24 weekend schedule values
    occupants_weekend_sch = OpenStudio::Measure::OSArgument::makeStringArgument("occupants_weekend_sch", true)
    occupants_weekend_sch.setDisplayName("Occupants Weekend schedule")
    occupants_weekend_sch.setDescription("Specify the 24-hour weekend schedule.")
    occupants_weekend_sch.setDefaultValue("1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 0.88, 0.41, 0.24, 0.24, 0.24, 0.24, 0.24, 0.24, 0.24, 0.29, 0.55, 0.90, 0.90, 0.90, 1.00, 1.00, 1.00")
    args << occupants_weekend_sch

    # Make a string argument for 12 monthly schedule values
    occupants_monthly_sch = OpenStudio::Measure::OSArgument::makeStringArgument("occupants_monthly_sch", true)
    occupants_monthly_sch.setDisplayName("Occupants Month schedule")
    occupants_monthly_sch.setDescription("Specify the 12-month schedule.")
    occupants_monthly_sch.setDefaultValue("1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0")
    args << occupants_monthly_sch

    # make a double argument for left neighbor offset
    left_neighbor_offset = OpenStudio::Measure::OSArgument::makeDoubleArgument("neighbor_left_offset", true)
    left_neighbor_offset.setDisplayName("Neighbor Left Offset")
    left_neighbor_offset.setUnits("ft")
    left_neighbor_offset.setDescription("The minimum distance between the simulated house and the neighboring house to the left (not including eaves). A value of zero indicates no neighbors.")
    left_neighbor_offset.setDefaultValue(10.0)
    args << left_neighbor_offset

    # make a double argument for right neighbor offset
    right_neighbor_offset = OpenStudio::Measure::OSArgument::makeDoubleArgument("neighbor_right_offset", true)
    right_neighbor_offset.setDisplayName("Neighbor Right Offset")
    right_neighbor_offset.setUnits("ft")
    right_neighbor_offset.setDescription("The minimum distance between the simulated house and the neighboring house to the right (not including eaves). A value of zero indicates no neighbors.")
    right_neighbor_offset.setDefaultValue(10.0)
    args << right_neighbor_offset

    # make a double argument for back neighbor offset
    back_neighbor_offset = OpenStudio::Measure::OSArgument::makeDoubleArgument("neighbor_back_offset", true)
    back_neighbor_offset.setDisplayName("Neighbor Back Offset")
    back_neighbor_offset.setUnits("ft")
    back_neighbor_offset.setDescription("The minimum distance between the simulated house and the neighboring house to the back (not including eaves). A value of zero indicates no neighbors.")
    back_neighbor_offset.setDefaultValue(0.0)
    args << back_neighbor_offset

    # make a double argument for front neighbor offset
    front_neighbor_offset = OpenStudio::Measure::OSArgument::makeDoubleArgument("neighbor_front_offset", true)
    front_neighbor_offset.setDisplayName("Neighbor Front Offset")
    front_neighbor_offset.setUnits("ft")
    front_neighbor_offset.setDescription("The minimum distance between the simulated house and the neighboring house to the front (not including eaves). A value of zero indicates no neighbors.")
    front_neighbor_offset.setDefaultValue(0.0)
    args << front_neighbor_offset

    # make a double argument for orientation
    orientation = OpenStudio::Measure::OSArgument::makeDoubleArgument("orientation", true)
    orientation.setDisplayName("Azimuth")
    orientation.setUnits("degrees")
    orientation.setDescription("The house's azimuth is measured clockwise from due south when viewed from above (e.g., South=0, West=90, North=180, East=270).")
    orientation.setDefaultValue(180.0)
    args << orientation

    # make a string argument for unit level
    level = OpenStudio::Measure::OSArgument::makeStringArgument("level", true)
    level.setDisplayName("Unit Level")
    level.setDescription("The level of the unit (Top, Middle, Bottom)")
    level.setDefaultValue("Bottom")
    args << level

    # make a string argument for unit horizontal location
    horz_location = OpenStudio::Measure::OSArgument::makeStringArgument("horz_location", true)
    horz_location.setDisplayName("Horizontal Location of the Unit")
    horz_location.setDescription("The horizontal location of the unit when viewing the front of the building (Left, Middle, Right)")
    horz_location.setDefaultValue("Left")
    args << horz_location

    # make a bool argument for back units
    has_rear_units = OpenStudio::Measure::OSArgument::makeBoolArgument("has_rear_units", true)
    has_rear_units.setDisplayName("Rear units boolean")
    has_rear_units.setDescription("Indicates if the unit has another unit behind it")
    has_rear_units.setDefaultValue(true)
    args << has_rear_units

    # make a bool argument for minimal collapsed building
    minimal_collapsed = OpenStudio::Measure::OSArgument::makeBoolArgument("minimal_collapsed", true)
    minimal_collapsed.setDisplayName("Minimal Collapsed Building")
    minimal_collapsed.setDescription("Collapse the building down into only corner, end, and/or middle units.")
    minimal_collapsed.setDefaultValue(false)
    args << minimal_collapsed

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    model_spaces = model.getSpaces

    unit_ffa = UnitConversions.convert(runner.getDoubleArgumentValue("unit_ffa", user_arguments), "ft^2", "m^2")
    wall_height = UnitConversions.convert(runner.getDoubleArgumentValue("wall_height", user_arguments), "ft", "m")
    num_floors = runner.getIntegerArgumentValue("num_floors", user_arguments)
    num_units = runner.getIntegerArgumentValue("num_units", user_arguments)
    unit_aspect_ratio = runner.getDoubleArgumentValue("unit_aspect_ratio", user_arguments)
    corridor_position = runner.getStringArgumentValue("corridor_position", user_arguments)
    corridor_width = UnitConversions.convert(runner.getDoubleArgumentValue("corridor_width", user_arguments), "ft", "m")
    inset_width = UnitConversions.convert(runner.getDoubleArgumentValue("inset_width", user_arguments), "ft", "m")
    inset_depth = UnitConversions.convert(runner.getDoubleArgumentValue("inset_depth", user_arguments), "ft", "m")
    inset_position = runner.getStringArgumentValue("inset_position", user_arguments)
    balcony_depth = UnitConversions.convert(runner.getDoubleArgumentValue("balcony_depth", user_arguments), "ft", "m")
    foundation_type = runner.getStringArgumentValue("foundation_type", user_arguments)
    foundation_height = runner.getDoubleArgumentValue("foundation_height", user_arguments)
    eaves_depth = UnitConversions.convert(runner.getDoubleArgumentValue("eaves_depth", user_arguments), "ft", "m")
    num_br = runner.getStringArgumentValue("num_bedrooms", user_arguments).split(",").map(&:strip)
    num_ba = runner.getStringArgumentValue("num_bathrooms", user_arguments).split(",").map(&:strip)
    num_occupants = runner.getStringArgumentValue("num_occupants", user_arguments)
    occupants_weekday_sch = runner.getStringArgumentValue("occupants_weekday_sch", user_arguments)
    occupants_weekend_sch = runner.getStringArgumentValue("occupants_weekend_sch", user_arguments)
    occupants_monthly_sch = runner.getStringArgumentValue("occupants_monthly_sch", user_arguments)
    left_neighbor_offset = UnitConversions.convert(runner.getDoubleArgumentValue("neighbor_left_offset", user_arguments), "ft", "m")
    right_neighbor_offset = UnitConversions.convert(runner.getDoubleArgumentValue("neighbor_right_offset", user_arguments), "ft", "m")
    back_neighbor_offset = UnitConversions.convert(runner.getDoubleArgumentValue("neighbor_back_offset", user_arguments), "ft", "m")
    front_neighbor_offset = UnitConversions.convert(runner.getDoubleArgumentValue("neighbor_front_offset", user_arguments), "ft", "m")
    orientation = runner.getDoubleArgumentValue("orientation", user_arguments)

    level = runner.getStringArgumentValue("level", user_arguments)
    horz_location = runner.getStringArgumentValue("horz_location", user_arguments)
    has_rear_units = runner.getBoolArgumentValue("has_rear_units", user_arguments)

    if foundation_type == "slab"
      foundation_height = 0.0
    elsif foundation_type == "unfinished basement"
      foundation_height = 8.0
    end
    num_units_per_floor = num_units / num_floors
    num_units_per_floor_actual = num_units_per_floor
    if (((num_units_per_floor == 1) or (num_units_per_floor % 2 != 0))) or (has_rear_units == false) # no rear units
      unit_depth = 1
      unit_width = num_units_per_floor
    elsif has_rear_units == true
      unit_depth = 2
      unit_width = num_units_per_floor / 2
    end

    # error checking
    if model_spaces.size > 0
      runner.registerError("Starting model is not empty.")
      return false
    end
    if foundation_type == "crawlspace" and (foundation_height < 1.5 or foundation_height > 5.0)
      runner.registerError("The crawlspace height can be set between 1.5 and 5 ft.")
      return false
    end
    if num_units % num_floors != 0
      runner.registerError("The number of units must be divisible by the number of floors.")
      return false
    end
    if (unit_depth == 1) and (corridor_position == "Double-Loaded Interior" or corridor_position == "Double Exterior")
      if has_rear_units
        runner.registerWarning("Specified incompatible corridor; setting corridor position to 'Single Exterior (Front)' and adjacent rear units to 'false'.")
        has_rear_units = false
      else
        runner.registerWarning("Specified incompatible corridor; setting corridor position to 'Single Exterior (Front)'.")
      end
      corridor_position = "Single Exterior (Front)"
    end
    if (unit_depth == 1) and (has_rear_units == true)
      runner.registerWarning("Specified incompatible rear adjacency option; setting adjacent rear units to 'false'.")
      has_rear_units = false
      unit_depth = 1
      unit_width = num_units_per_floor
    end
    if unit_aspect_ratio < 0
      runner.registerError("Invalid aspect ratio entered.")
      return false
    end
    if corridor_width == 0 and corridor_position != "None"
      corridor_position = "None"
    end
    if corridor_position == "None"
      corridor_width = 0
    end
    if corridor_width < 0
      runner.registerError("Invalid corridor width entered.")
      return false
    end
    if balcony_depth > 0 and inset_width * inset_depth == 0
      runner.registerWarning("Specified a balcony, but there is no inset.")
      balcony_depth = 0
    end
    if unit_width < 3 and horz_location == "Middle"
      runner.registerError("No middle horizontal location exists.")
      return false
    end

    # Convert to SI
    foundation_height = UnitConversions.convert(foundation_height, "ft", "m")
    space_types_hash = {}

    # starting spaces
    runner.registerInitialCondition("The building started with #{model_spaces.size} spaces.")

    # calculate the dimensions of the unit
    footprint = unit_ffa + inset_width * inset_depth
    x = Math.sqrt(footprint / unit_aspect_ratio)
    y = footprint / x

    foundation_corr_polygon = nil
    foundation_front_polygon = nil
    foundation_back_polygon = nil

    # create the front prototype unit footprint
    nw_point = OpenStudio::Point3d.new(0, 0, 0)
    ne_point = OpenStudio::Point3d.new(x, 0, 0)
    sw_point = OpenStudio::Point3d.new(0, -y, 0)
    se_point = OpenStudio::Point3d.new(x, -y, 0)
    
    if inset_width * inset_depth > 0
      if inset_position == "Right"
        # unit footprint
        inset_point = OpenStudio::Point3d.new(x - inset_width, inset_depth - y, 0)
        front_point = OpenStudio::Point3d.new(x - inset_width, -y, 0)
        side_point = OpenStudio::Point3d.new(x, inset_depth - y, 0)
        living_polygon = Geometry.make_polygon(sw_point, nw_point, ne_point, side_point, inset_point, front_point)
        # unit balcony
        if balcony_depth > 0
          inset_point = OpenStudio::Point3d.new(x - inset_width, inset_depth - y, wall_height)
          side_point = OpenStudio::Point3d.new(x, inset_depth - y, wall_height)
          se_point = OpenStudio::Point3d.new(x, inset_depth - y - balcony_depth, wall_height)
          front_point = OpenStudio::Point3d.new(x - inset_width, inset_depth - y - balcony_depth, wall_height)
          shading_surface = OpenStudio::Model::ShadingSurface.new(OpenStudio::Point3dVector.new([front_point, se_point, side_point, inset_point]), model)
        end
      else
        # unit footprint
        inset_point = OpenStudio::Point3d.new(inset_width, inset_depth - y, 0)
        front_point = OpenStudio::Point3d.new(inset_width, -y, 0)
        side_point = OpenStudio::Point3d.new(0, inset_depth - y, 0)
        living_polygon = Geometry.make_polygon(side_point, nw_point, ne_point, se_point, front_point, inset_point)
        # unit balcony
        if balcony_depth > 0
          inset_point = OpenStudio::Point3d.new(inset_width, inset_depth - y, wall_height)
          side_point = OpenStudio::Point3d.new(0, inset_depth - y, wall_height)
          sw_point = OpenStudio::Point3d.new(0, inset_depth - y - balcony_depth, wall_height)
          front_point = OpenStudio::Point3d.new(inset_width, inset_depth - y - balcony_depth, wall_height)
          shading_surface = OpenStudio::Model::ShadingSurface.new(OpenStudio::Point3dVector.new([front_point, sw_point, side_point, inset_point]), model)
        end
      end
    else  
      living_polygon = Geometry.make_polygon(sw_point, nw_point, ne_point, se_point)
    end
    
    # foundation
    if foundation_height > 0 and foundation_front_polygon.nil?
      foundation_front_polygon = living_polygon
    end

    # create living zone
    living_zone = OpenStudio::Model::ThermalZone.new(model)
    living_zone.setName("living zone")

    # first floor front
    puts("living poly=", living_polygon)
    living_spaces_front = []
    living_space = OpenStudio::Model::Space::fromFloorPrint(living_polygon, wall_height, model)
    living_space = living_space.get
    living_space.setName("living space")
    if space_types_hash.keys.include? Constants.SpaceTypeLiving
      living_space_type = space_types_hash[Constants.SpaceTypeLiving]
    else
      living_space_type = OpenStudio::Model::SpaceType.new(model)
      living_space_type.setStandardsSpaceType(Constants.SpaceTypeLiving)
      space_types_hash[Constants.SpaceTypeLiving] = living_space_type
    end
    living_space.setSpaceType(living_space_type)
    living_space.setThermalZone(living_zone)

    # add the balcony
    if balcony_depth > 0
      shading_surface_group = OpenStudio::Model::ShadingSurfaceGroup.new(model)
      shading_surface_group.setSpace(living_space)
      shading_surface.setShadingSurfaceGroup(shading_surface_group)
    end
    living_spaces_front << living_space

    ##############################################################################################
    ##############################################################################################
    # Map unit location to adiabatic surfaces
    horz_hash = { "Left" => ["right"], "Right" => ["left"], "Middle" => ["left", "right"], "None" => [] }
    level_hash = { "Bottom" => ["RoofCeiling"], "Top" => ["Floor"], "Middle" => ["RoofCeiling", "Floor"], "None" => [] }
    adb_facade = horz_hash[horz_location]
    adb_level = level_hash[level]

    # Check levels
    if num_floors == 1
      adb_level = []
    end
    # Check for exposed left and right facades
    if num_units_per_floor == 1 or (num_units_per_floor == 2 and has_rear_units == true)
      adb_facade = []
    end
    if (has_rear_units == true)
      adb_facade += ["back"]
    end

    adiabatic_surf = adb_facade + horz_hash[horz_location] + level_hash[level]
    # Make surfaces adiabatic
    puts(model.getSpaces)
    model.getSpaces.each do |space|
      # puts(space)
      # Store has_rear_units to call in the door geometry measure
      space.surfaces.each do |surface|
        os_facade = Geometry.get_facade_for_surface(surface)
        if surface.surfaceType == "Wall"
          if adb_facade.include? os_facade
            x_ft = UnitConversions.convert(x, "m", "ft")
            max_x = Geometry.getSurfaceXValues([surface]).max
            min_x = Geometry.getSurfaceXValues([surface]).min
            next if ((max_x - x_ft).abs >= 0.01) and min_x > 0
            surface.setOutsideBoundaryCondition("Adiabatic")
          end
        else
          if (adb_level.include? surface.surfaceType)
            surface.setOutsideBoundaryCondition("Adiabatic")
          end
        end
      end
    end
    ##############################################################################################
    ##############################################################################################

    # create the unit
    # unit_spaces_hash = {}
    # unit_spaces_hash[1] = living_spaces_front

    if (corridor_position == "Double-Loaded Interior")
      interior_corridor_width = corridor_width / 2 # Only half the corridor is attached to a unit
      # corridors
      if corridor_width > 0
        # create the prototype corridor
        nw_point = OpenStudio::Point3d.new(0, interior_corridor_width, 0)
        ne_point = OpenStudio::Point3d.new(x, interior_corridor_width, 0)
        sw_point = OpenStudio::Point3d.new(0, 0, 0)
        se_point = OpenStudio::Point3d.new(x, 0, 0)
        corr_polygon = Geometry.make_polygon(sw_point, nw_point, ne_point, se_point)

        if foundation_height > 0 and foundation_corr_polygon.nil?
          foundation_corr_polygon = corr_polygon
        end

        # create corridor zone
        corridor_zone = OpenStudio::Model::ThermalZone.new(model)
        corridor_zone.setName("corridor zone")
        corridor_space = OpenStudio::Model::Space::fromFloorPrint(corr_polygon, wall_height, model)
        corridor_space = corridor_space.get
        corridor_space_name = "corridor space"
        corridor_space.setName(corridor_space_name)
        if space_types_hash.keys.include? Constants.SpaceTypeCorridor
          corridor_space_type = space_types_hash[Constants.SpaceTypeCorridor]
        else
          corridor_space_type = OpenStudio::Model::SpaceType.new(model)
          corridor_space_type.setStandardsSpaceType(Constants.SpaceTypeCorridor)
          space_types_hash[Constants.SpaceTypeCorridor] = corridor_space_type
        end
        corridor_space.setSpaceType(corridor_space_type)
        corridor_space.setThermalZone(corridor_zone)

        # Make back wall of corridor adiabatic if there are rear units
        if has_rear_units == true
          corridor_space.surfaces.each do |surface|
            os_facade = Geometry.get_facade_for_surface(surface)
          end
        end
      end

    elsif corridor_position == "Double Exterior" or corridor_position == "Single Exterior (Front)"
      interior_corridor_width = 0
      # front access
      nw_point = OpenStudio::Point3d.new(0, -y, wall_height)
      sw_point = OpenStudio::Point3d.new(0, -y - corridor_width, wall_height)
      ne_point = OpenStudio::Point3d.new(x, -y, wall_height)
      se_point = OpenStudio::Point3d.new(x, -y - corridor_width, wall_height)

      shading_surface = OpenStudio::Model::ShadingSurface.new(OpenStudio::Point3dVector.new([sw_point, se_point, ne_point, nw_point]), model)
      shading_surface_group = OpenStudio::Model::ShadingSurfaceGroup.new(model)
      shading_surface.setShadingSurfaceGroup(shading_surface_group)
      shading_surface.setName("Corridor shading")

      # rear access
      # nw_point = OpenStudio::Point3d.new(0, y + corridor_width, wall_height)
      # sw_point = OpenStudio::Point3d.new(0, y, wall_height)
      # ne_point = OpenStudio::Point3d.new(x, y + corridor_width, wall_height)
      # se_point = OpenStudio::Point3d.new(x, y, wall_height)

      # shading_surface = OpenStudio::Model::ShadingSurface.new(OpenStudio::Point3dVector.new([sw_point, se_point, ne_point, nw_point]), model)

      # shading_surface_group = OpenStudio::Model::ShadingSurfaceGroup.new(model)
      # shading_surface.setShadingSurfaceGroup(shading_surface_group)
      # shading_surface.setName("Double Exterior Corridor Rear")
    end

    # if corridor_position == "Single Exterior (Front)"
    # nw_point = OpenStudio::Point3d.new(0, -y, wall_height)
    # sw_point = OpenStudio::Point3d.new(0, -y - corridor_width, wall_height)
    # ne_point = OpenStudio::Point3d.new(x, -y, wall_height)
    # se_point = OpenStudio::Point3d.new(x, -y - corridor_width, wall_height)

    # shading_surface = OpenStudio::Model::ShadingSurface.new(OpenStudio::Point3dVector.new([sw_point, se_point, ne_point, nw_point]), model)

    # shading_surface_group = OpenStudio::Model::ShadingSurfaceGroup.new(model)
    # shading_surface.setShadingSurfaceGroup(shading_surface_group)
    # shading_surface.setName("Single Exterior Corridor Front")
    # end

    # foundation
    if foundation_height > 0
      foundation_spaces = []

      # foundation corridor
      if corridor_width > 0 and corridor_position == "Double-Loaded Interior"
        corridor_space = OpenStudio::Model::Space::fromFloorPrint(foundation_corr_polygon, foundation_height, model)
        corridor_space = corridor_space.get
        m = Geometry.initialize_transformation_matrix(OpenStudio::Matrix.new(4, 4, 0))
        m[2, 3] = foundation_height
        corridor_space.changeTransformation(OpenStudio::Transformation.new(m))
        corridor_space.setXOrigin(0)
        corridor_space.setYOrigin(0)
        corridor_space.setZOrigin(0)

        foundation_spaces << corridor_space
      end

      # foundation front
      foundation_space_front = []
      puts("Foundation:")
      foundation_space = OpenStudio::Model::Space::fromFloorPrint(foundation_front_polygon, foundation_height, model)
      foundation_space = foundation_space.get
      m = Geometry.initialize_transformation_matrix(OpenStudio::Matrix.new(4, 4, 0))
      m[2, 3] = foundation_height
      foundation_space.changeTransformation(OpenStudio::Transformation.new(m))
      foundation_space.setXOrigin(0)
      foundation_space.setYOrigin(0)
      foundation_space.setZOrigin(0)

      foundation_space_front << foundation_space
      foundation_spaces << foundation_space

      # put all of the spaces in the model into a vector
      spaces = OpenStudio::Model::SpaceVector.new
      model.getSpaces.each do |space|
        spaces << space
      end

      # intersect and match surfaces for each space in the vector
      OpenStudio::Model.intersectSurfaces(spaces)
      OpenStudio::Model.matchSurfaces(spaces)

      if ["crawlspace", "unfinished basement"].include? foundation_type
        foundation_space = Geometry.make_one_space_from_multiple_spaces(model, foundation_spaces)
        if foundation_type == "crawlspace"
          foundation_space.setName("crawl space")
          foundation_zone = OpenStudio::Model::ThermalZone.new(model)
          foundation_zone.setName("crawl zone")
          foundation_space.setThermalZone(foundation_zone)
          foundation_space_type_name = Constants.SpaceTypeCrawl
        elsif foundation_type == "unfinished basement"
          foundation_space.setName("unfinished basement space")
          foundation_zone = OpenStudio::Model::ThermalZone.new(model)
          foundation_zone.setName("unfinished basement zone")
          foundation_space.setThermalZone(foundation_zone)
          foundation_space_type_name = Constants.SpaceTypeUnfinishedBasement
        end
        if space_types_hash.keys.include? foundation_space_type_name
          foundation_space_type = space_types_hash[foundation_space_type_name]
        else
          foundation_space_type = OpenStudio::Model::SpaceType.new(model)
          foundation_space_type.setStandardsSpaceType(foundation_space_type_name)
          space_types_hash[foundation_space_type_name] = foundation_space_type
        end
        foundation_space.setSpaceType(foundation_space_type)
      end

      # set foundation walls to ground
      spaces = model.getSpaces
      spaces.each do |space|
        if Geometry.get_space_floor_z(space) + UnitConversions.convert(space.zOrigin, "m", "ft") < 0
          surfaces = space.surfaces
          surfaces.each do |surface|
            next if surface.surfaceType.downcase != "wall"
      
            surface.setOutsideBoundaryCondition("Foundation")
          end
        end
      end

    end

    # unit_spaces_hash.each do |unit_num, spaces|
    #   # Store building unit information
    #   unit = OpenStudio::Model::BuildingUnit.new(model)
    #   unit.setBuildingUnitType(Constants.BuildingUnitTypeResidential)
    #   unit.setName(Constants.ObjectNameBuildingUnit(unit_num))
    #   spaces.each do |space|
    #     space.setBuildingUnit(unit)
    #   end
    # end

    # put all of the spaces in the model into a vector
    spaces = OpenStudio::Model::SpaceVector.new
    model.getSpaces.each do |space|
      spaces << space
    end

    # intersect and match surfaces for each space in the vector
    OpenStudio::Model.intersectSurfaces(spaces)
    OpenStudio::Model.matchSurfaces(spaces)

    # make all surfaces adjacent to corridor spaces into adiabatic surfaces
    model.getSpaces.each do |space|
      space.surfaces.each do |surface|
      end
      next unless Geometry.is_corridor(space)

      space.surfaces.each do |surface|
        if surface.adjacentSurface.is_initialized # only set to adiabatic if the corridor surface is adjacent to another surface
          surface.adjacentSurface.get.setOutsideBoundaryCondition("Adiabatic")
          surface.setOutsideBoundaryCondition("Adiabatic")
        end
      end
    end

    # set foundation outside boundary condition to Kiva "foundation"
    model.getSurfaces.each do |surface|
      next if surface.outsideBoundaryCondition.downcase != "ground"

      surface.setOutsideBoundaryCondition("Foundation")
    end

    # Store number of units
    model.getBuilding.setStandardsNumberOfLivingUnits(num_units)

    # Store number of stories
    model.getBuilding.setStandardsNumberOfAboveGroundStories(num_floors)
    if foundation_type == "unfinished basement"
      num_floors += 1
    end
    model.getBuilding.setStandardsNumberOfStories(num_floors)

    # Store the building type
    model.getBuilding.setStandardsBuildingType(Constants.BuildingTypeMultifamily)

    result = Geometry.process_beds_and_baths(model, runner, num_br, num_ba)
    unless result
      return false
    end

    result = Geometry.process_occupants(model, runner, num_occupants, occ_gain = 384.0, sens_frac = 0.573, lat_frac = 0.427, occupants_weekday_sch, occupants_weekend_sch, occupants_monthly_sch)
    unless result
      return false
    end

    result = Geometry.process_eaves(model, runner, eaves_depth, Constants.RoofStructureTrussCantilever)
    unless result
      return false
    end

    result = Geometry.process_neighbors(model, runner, left_neighbor_offset, right_neighbor_offset, back_neighbor_offset, front_neighbor_offset)
    unless result
      return false
    end

    result = Geometry.process_orientation(model, runner, orientation)
    unless result
      return false
    end

    # reporting final condition of model
    runner.registerFinalCondition("The building finished with #{model.getSpaces.size} spaces.")

    spaces = model.getSpaces
    spaces.each do |space|
      if Geometry.get_space_floor_z(space) + UnitConversions.convert(space.zOrigin, "m", "ft") < 0
        surfaces = space.surfaces
        surfaces.each do |surface|
          puts(surface)
          next if surface.surfaceType.downcase != "wall"
    
          surface.setOutsideBoundaryCondition("Foundation")
        end
      end
    end


    return true
  end
end

# register the measure to be used by the application
CreateResidentialMultifamilyGeometry.new.registerWithApplication