package custommetrics

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestMetricIntake(t *testing.T) {
	tests := []struct {
		desc        string
		payloadjson string
	}{
		{
			"valid series",
			`{"series":[{"metric":"dd.go.testing.1","points":[[1417059516,1.0],[1417059517,2],[1417059518,1.0],[1417059519,2],[2323232.0,22.9],[1417059516,1.0],[1417059517,2],[2323232.0,22.10],[2323232.0,22.11],[2323232.0,22.12]],"tags":["x:y1","z:zz1","g:k1","tt:1","tz:10"],"device":"/something/else","type":"gauge","interval":10,"SourceTypeName":"blah","HostTags":["hosta:x","hostb:y","hostc:z","sdfjs:kdsd","eere:s322"]}]}`,
		},
	}

	for i, tt := range tests {
		t.Run(fmt.Sprintf("#%d %s", i, tt.desc), func(t *testing.T) {
			intake := NewMetricsIntake()
			intake.Start()
			defer intake.Stop()

			err := intake.Send([]byte(tt.payloadjson))
			require.NoError(t, err)
		})
	}
}
