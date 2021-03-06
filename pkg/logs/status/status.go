// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2018 Datadog, Inc.

package status

import (
	"strings"

	"github.com/DataDog/datadog-agent/pkg/logs/config"
)

var (
	builder *Builder
)

// Source provides some information about a logs source.
type Source struct {
	Type          string            `json:"type"`
	Configuration map[string]string `json:"configuration"`
	Status        string            `json:"status"`
	Inputs        []string          `json:"inputs"`
}

// Integration provides some information about a logs integration.
type Integration struct {
	Name    string   `json:"name"`
	Sources []Source `json:"sources"`
}

// Status provides some information about logs-agent.
type Status struct {
	IsRunning    bool          `json:"is_running"`
	Integrations []Integration `json:"integrations"`
}

// Builder is used to build the status.
type Builder struct {
	sources []*config.LogSource
}

// Initialize instantiates a builder that holds the sources required to build the current status later on.
func Initialize(sources []*config.LogSource) {
	builder = &Builder{
		sources: sources,
	}
}

// Get returns the status of the logs-agent computed on the fly.
func Get() Status {
	// Sort sources by name (ie. by integration name ~= file name)
	sources := make(map[string][]*config.LogSource)
	for _, source := range builder.sources {
		if _, exists := sources[source.Name]; !exists {
			sources[source.Name] = []*config.LogSource{}
		}
		sources[source.Name] = append(sources[source.Name], source)
	}
	// Convert to json
	var integrations []Integration
	for name, sourceList := range sources {
		var sources []Source
		for _, source := range sourceList {
			var status string
			if source.Status.IsPending() {
				status = "Pending"
			} else if source.Status.IsSuccess() {
				status = "OK"
			} else if source.Status.IsError() {
				status = source.Status.GetError()
			}
			sources = append(sources, Source{
				Type:          source.Config.Type,
				Configuration: toDictionary(source.Config),
				Status:        status,
				Inputs:        source.GetInputs(),
			})
		}
		integrations = append(integrations, Integration{Name: name, Sources: sources})
	}
	return Status{
		IsRunning:    true,
		Integrations: integrations,
	}
}

// toDictionary returns a representation of the configuration
func toDictionary(c *config.LogsConfig) map[string]string {
	dictionary := make(map[string]string)
	switch c.Type {
	case config.TCPType, config.UDPType:
		dictionary["Port"] = string(c.Port)
	case config.FileType:
		dictionary["Path"] = c.Path
	case config.DockerType:
		dictionary["Image"] = c.Image
		dictionary["Label"] = c.Label
		dictionary["Name"] = c.Name
	case config.JournaldType:
		dictionary["IncludeUnits"] = strings.Join(c.IncludeUnits, ", ")
		dictionary["ExcludeUnits"] = strings.Join(c.ExcludeUnits, ", ")
	case config.WindowsEventType:
		dictionary["ChannelPath"] = c.ChannelPath
		dictionary["Query"] = c.Query
	}
	for k, v := range dictionary {
		if v == "" {
			delete(dictionary, k)
		}
	}
	return dictionary
}
