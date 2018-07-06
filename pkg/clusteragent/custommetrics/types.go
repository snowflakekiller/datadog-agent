package custommetrics

// CustomMetricValue
type CustomMetricValue struct {
	DescribedObject ObjectReference `json:"describedObject"`
	MetricName      string          `json:"metricName"`
	Timestamp       float64         `json:"ts"`
	Value           float64         `json:"value"`
}

// ObjectReference
type ObjectReference struct {
	Kind       string `json:"kind"`
	Name       string `json:"name"`
	APIVersion string `json:"apiVersion,omitempty"`
}
