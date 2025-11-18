// Copyright 2021 Google LLC All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"strings"
	"time"

	sdk "agones.dev/agones/sdks/go"
)

// main intercepts the stdout of the Minetest gameserver and uses it
// to determine if the game server is ready or not.
func main() {
	input := flag.String("i", "", "path to minetestserver.sh")
	args := flag.String("args", "", "additional arguments to pass to the script")
	flag.Parse()

	argsList := strings.Split(strings.Trim(strings.TrimSpace(*args), "'"), " ")
	fmt.Println(">>> Connecting to Agones with the SDK")
	s, err := sdk.NewSDK()
	if err != nil {
		log.Fatalf(">>> Could not connect to sdk: %v", err)
	}

	fmt.Println(">>> Starting health checking")
	go doHealth(s)

	fmt.Println(">>> Starting wrapper for Minetest!")
	fmt.Printf(">>> Path to Minetest server script: %s %v\n", *input, argsList)

	// We're going to use a pipe so we can read the stdout of the process
	r, w := io.Pipe()

	cmd := exec.Command(*input, argsList...) // #nosec
	cmd.Stderr = os.Stderr
	cmd.Stdout = io.MultiWriter(os.Stdout, w)

	// Use a scanner to read the output line by line
	go func() {
		scanner := bufio.NewScanner(r)
		isReady := false
		for scanner.Scan() {
			line := scanner.Text()
			// Minetest will say "listening on [::]:30000." when ready.
			if !isReady && strings.HasSuffix(line, "listening on [::]:30000.") {
				isReady = true
				fmt.Printf(">>> Found 'listening' statement in line: '%s', marking server as ready.\n", line)
				err := s.Ready()
				if err != nil {
					log.Fatalf("Could not send ready message: %v", err)
				}
			}
		}
		if err := scanner.Err(); err != nil {
			log.Printf("Error reading stdout: %v", err)
		}
	}()

	if err := cmd.Start(); err != nil {
		log.Fatalf(">>> Error Starting Cmd %v", err)
	}
	err = cmd.Wait()
	log.Fatal(">>> Minetest shutdown unexpectantly", err)
}

// doHealth sends the regular Health Pings
func doHealth(sdk *sdk.SDK) {
	tick := time.Tick(2 * time.Second)
	for {
		if err := sdk.Health(); err != nil {
			log.Fatalf("[wrapper] Could not send health ping, %v", err)
		}
		<-tick
	}
}
