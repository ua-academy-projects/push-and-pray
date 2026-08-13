package schedule

import "time"

func LatestSlot(now time.Time, hours []int, location *time.Location) time.Time {
	localNow := now.In(location)
	for index := len(hours) - 1; index >= 0; index-- {
		candidate := time.Date(
			localNow.Year(), localNow.Month(), localNow.Day(), hours[index], 0, 0, 0, location,
		)
		if !candidate.After(localNow) {
			return candidate.UTC()
		}
	}
	previousDay := localNow.AddDate(0, 0, -1)
	return time.Date(
		previousDay.Year(), previousDay.Month(), previousDay.Day(), hours[len(hours)-1], 0, 0, 0, location,
	).UTC()
}

func NextSlot(now time.Time, hours []int, location *time.Location) time.Time {
	localNow := now.In(location)
	for _, hour := range hours {
		candidate := time.Date(
			localNow.Year(), localNow.Month(), localNow.Day(), hour, 0, 0, 0, location,
		)
		if candidate.After(localNow) {
			return candidate.UTC()
		}
	}
	nextDay := localNow.AddDate(0, 0, 1)
	return time.Date(
		nextDay.Year(), nextDay.Month(), nextDay.Day(), hours[0], 0, 0, 0, location,
	).UTC()
}
