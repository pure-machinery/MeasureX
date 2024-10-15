package mx_chain



tolerance_class_designation :: enum 
{
	FINE,
	MEDIUM,
	COARSE,
	VERY_COARSE,
}


FetchToleranceRangeISO2862 :: proc(value: f64, designation: tolerance_class_designation) -> (f64, f64)
{
	for entry in tolerance_table {
		if abs(value) >= entry.lower_value && abs(value) < entry.upper_value {
			tolerance := entry.tolerance_range[designation];
			return -tolerance, tolerance; 
		}
	}

	return 0.0, 0.0;
}

tolerance_class_range :: struct 
{
	lower_value: f64,
	upper_value: f64,

	// Values are symmetric (eg. +/- 2.0).
	tolerance_range: [cast(int) len(tolerance_class_designation)]f64,
}

tolerance_table : []tolerance_class_range =  {
	tolerance_class_range {
		lower_value = 0.5,
		upper_value = 3.0,

		tolerance_range =  { 0.05, 0.1, 0.2, 0.0, },
		},
	tolerance_class_range {
		lower_value = 3.0,
		upper_value = 6.0,

		tolerance_range = { 0.05, 0.1, 0.3, 0.5, },
	},
	tolerance_class_range {
		lower_value = 6.0,
		upper_value = 30.0,

		tolerance_range = { 0.1, 0.2, 0.5, 1.0, },
	},
	tolerance_class_range {
		lower_value = 30.0,
		upper_value = 120.0,

		tolerance_range = 
			{ 0.15, 0.3, 0.8, 1.5, },
	},
	tolerance_class_range {
		lower_value = 120.0,
		upper_value = 400.0,

		tolerance_range = 
			{ 0.2, 0.5, 1.2, 2.5, },
	},
	tolerance_class_range {
		lower_value = 400.0,
		upper_value = 1000.0,

		tolerance_range = 
			{ 0.3, 0.8, 2.0, 4.0, },
	},
	tolerance_class_range {
		lower_value = 1000.0,
		upper_value = 2000.0,

		tolerance_range = { 0.5, 1.2, 3.0, 6.0, },
	},
	tolerance_class_range {
		lower_value = 2000.0,
		upper_value = 4000.0,

		tolerance_range = { 0.0, 2.0, 4.0, 8.0, },
	},
};