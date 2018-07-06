// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2017 Datadog, Inc.

package custommetrics

import (
	"encoding/json"
	"sync"

	"github.com/DataDog/datadog-agent/pkg/metrics"
	"github.com/DataDog/datadog-agent/pkg/util/log"
)

const (
	seriesChannelSize = 256
)

// DefaultMetricsIntake
var DefaultMetricsIntake = NewMetricsIntake()

// MetricsIntake
type MetricsIntake struct {
	seriesCh chan metrics.Serie

	stopCh chan struct{}
	wg     sync.WaitGroup
}

// NewMetricsIntake
func NewMetricsIntake() *MetricsIntake {
	return &MetricsIntake{
		seriesCh: make(chan metrics.Serie, seriesChannelSize),
		stopCh:   make(chan struct{}),
	}
}

// Start
func (m *MetricsIntake) Start() {
	log.Info("Starting metrics intake process...")
	m.wg.Add(1)
	go m.start()
}

func (m *MetricsIntake) start() {
	defer m.wg.Done()

	for {
		select {
		case <-m.stopCh:
			return
		case serie := <-m.seriesCh:
			if len(serie.Points) == 0 {
				log.Tracef("Dropping serie with no points: %v", serie)
				continue
			}
			log.Tracef("Processing serie: %v", serie)

			// metric := CustomMetricValue{
			// 	MetricName: serie.Name,
			// 	Timestamp:  serie.Points[0].Ts,
			// 	Value:      serie.Points[0].Value,
			// }
			// 1. Read from store and update value
			// 2.
		}
	}
}

// Send
func (m *MetricsIntake) Send(b []byte) error {
	var payload string
	if err := json.Unmarshal(b, &payload); err != nil {
		return err
	}
	log.Tracef("Processing payload: %s", payload)
	// var serie metrics.Serie
	// m.seriesCh <- serie
	return nil
}

// Stop
func (m *MetricsIntake) Stop() {
	close(m.stopCh)
	m.wg.Wait()
}
