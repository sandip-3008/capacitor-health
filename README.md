# @interval-health/capacitor-health

A Capacitor plugin to interact with health data from **Apple HealthKit** (iOS) and **Health Connect** (Android). This plugin provides a unified JavaScript API to read and write health and fitness data across both platforms.

---

## 📦 Installation

```bash
npm install @interval-health/capacitor-health
```

After installation, sync your native projects:

```bash
npx cap sync
```

---

## 🚀 Supported Platforms

| Platform | Implementation | Minimum Version |
|----------|---------------|-----------------|
| **iOS** | Apple HealthKit | iOS 13.0+ |
| **Android** | Health Connect | Android 9.0+ (API 28) |
| **Web** | Not supported | - |

### Platform Requirements

#### iOS
- Xcode 14.0 or later
- iOS deployment target: 13.0+
- You must add the required usage descriptions to your `Info.plist`

#### Android
- Android Studio Arctic Fox or later
- Minimum SDK: 28 (Android 9.0)
- Target SDK: 34+
- Health Connect app must be installed on the device

---

## 🔐 Permissions & Setup

### iOS Setup

Add the following keys to your `ios/App/App/Info.plist` file:

```xml
<key>NSHealthShareUsageDescription</key>
<string>This app needs access to read your health data.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>This app needs access to write health data.</string>
```

Enable the **HealthKit** capability in your Xcode project:
1. Open your project in Xcode
2. Select your app target
3. Go to **Signing & Capabilities**
4. Click **+ Capability** and add **HealthKit**

### Android Setup

Add the Health Connect permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest>
    <!-- Health Connect permissions -->
    <uses-permission android:name="android.permission.health.READ_STEPS"/>
    <uses-permission android:name="android.permission.health.WRITE_STEPS"/>
    <uses-permission android:name="android.permission.health.READ_DISTANCE"/>
    <uses-permission android:name="android.permission.health.WRITE_DISTANCE"/>
    <uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED"/>
    <uses-permission android:name="android.permission.health.WRITE_ACTIVE_CALORIES_BURNED"/>
    <uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
    <uses-permission android:name="android.permission.health.WRITE_HEART_RATE"/>
    <uses-permission android:name="android.permission.health.READ_WEIGHT"/>
    <uses-permission android:name="android.permission.health.WRITE_WEIGHT"/>
    <uses-permission android:name="android.permission.health.READ_SLEEP"/>
    <uses-permission android:name="android.permission.health.WRITE_SLEEP"/>

    <application>
        <!-- Required for Health Connect integration -->
        <activity-alias
            android:name="ViewPermissionUsageActivity"
            android:exported="true"
            android:targetActivity=".MainActivity"
            android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
            <intent-filter>
                <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
            </intent-filter>
        </activity-alias>
    </application>
</manifest>
```

**Note**: Users must have the **Health Connect** app installed on their Android device. If not installed, the plugin will report that health data is unavailable.

---

## 📖 Usage Guide

### Import the Plugin

```typescript
import { Health } from '@interval-health/capacitor-health';
```

### Complete Workflow Example

Here's a typical flow for working with health data:

```typescript
import { Health } from '@interval-health/capacitor-health';

async function setupHealthData() {
  // 1. Check if health services are available
  const availability = await Health.isAvailable();
  
  if (!availability.available) {
    console.error('Health data unavailable:', availability.reason);
    return;
  }

  // 2. Request authorization for data types
  const authStatus = await Health.requestAuthorization({
    read: ['steps', 'heartRate', 'weight', 'sleep'],
    write: ['steps', 'weight']
  });

  console.log('Authorized to read:', authStatus.readAuthorized);
  console.log('Denied to read:', authStatus.readDenied);

  // 3. Read health samples
  const stepsData = await Health.readSamples({
    dataType: 'steps',
    startDate: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(), // 7 days ago
    endDate: new Date().toISOString(),
    limit: 100,
    ascending: false
  });

  console.log('Steps data:', stepsData.samples);

  // 4. Write a health sample
  await Health.saveSample({
    dataType: 'weight',
    value: 70.5,
    startDate: new Date().toISOString()
  });

  console.log('Weight saved successfully!');
}
```

---

## 📚 API Reference

### Health Data Types

The plugin supports the following health data types:

```typescript
export type HealthDataType = 
  | 'steps' 
  | 'distance' 
  | 'calories' 
  | 'heartRate' 
  | 'weight' 
  | 'sleep' 
  | 'mobility' 
  | 'activity' 
  | 'heart' 
  | 'body'
  | 'workout';
```

| Data Type | Description | Unit | iOS | Android | Read | Write |
|-----------|-------------|------|-----|---------|------|-------|
| `steps` | Step count | count | ✅ | ✅ | ✅ | ✅ |
| `distance` | Walking/running distance | meter | ✅ | ✅ | ✅ | ✅ |
| `calories` | Active calories burned | kilocalorie | ✅ | ✅ | ✅ | ✅ |
| `heartRate` | Heart rate | bpm (beats per minute) | ✅ | ✅ | ✅ | ✅ |
| `weight` | Body weight | kilogram | ✅ | ✅ | ✅ | ✅ |
| `sleep` | Sleep duration and stages | minute | ✅ | ❌ | ✅ | ✅ |
| `mobility` | Mobility metrics | mixed | ✅ | ❌ | ✅ | ❌ |
| `activity` | Activity metrics | mixed | ✅ | ❌ | ✅ | ❌ |
| `heart` | Heart health metrics | mixed | ✅ | ❌ | ✅ | ❌ |
| `body` | Body measurements | mixed | ✅ | ❌ | ✅ | ❌ |
| `workout` | Workout/exercise sessions | minute | ✅ | ❌ | ✅ | ❌ |

**Platform Support Notes**:
- **iOS** supports all 11 data types
- **Android** supports only 5 basic data types: `steps`, `distance`, `calories`, `heartRate`, and `weight`
- The `sleep`, `mobility`, `activity`, `heart`, `body`, and `workout` types are **iOS-only** and not available on Android
- Composite types (`mobility`, `activity`, `heart`, `body`, `workout`) are **read-only** on iOS

### Sleep States

When reading sleep data, each sample may include a `sleepState` property:

| State | Description |
|-------|-------------|
| `inBed` | User is in bed but not necessarily asleep |
| `asleep` | General sleep state (when specific stage unknown) |
| `awake` | User is awake during sleep period |
| `asleepCore` | Core/light sleep stage |
| `asleepDeep` | Deep sleep stage |
| `asleepREM` | REM (Rapid Eye Movement) sleep stage |
| `unknown` | Sleep state could not be determined |

### Workout Data

When reading workout data (`dataType: 'workout'`), the returned data structure includes:

```typescript
interface WorkoutData {
  date: string;           // ISO date (YYYY-MM-DD)
  type: string;           // Activity type (e.g., "Running", "Cycling", "Swimming")
  duration: number;       // Duration in minutes
  distance?: number;      // Distance in miles (optional)
  calories?: number;      // Calories burned (optional)
  source?: string;        // Source app name (optional)
  avgHeartRate?: number;  // Average heart rate in BPM (optional)
  maxHeartRate?: number;  // Maximum heart rate in BPM (optional)
  zones?: {               // Heart rate zones in minutes (optional)
    zone1?: number;       // 50-60% max HR
    zone2?: number;       // 60-70% max HR
    zone3?: number;       // 70-80% max HR
    zone4?: number;       // 80-90% max HR
    zone5?: number;       // 90-100% max HR
  };
}
```

**Supported Workout Types**: Running, Cycling, Walking, Swimming, Yoga, FunctionalStrengthTraining, TraditionalStrengthTraining, Elliptical, Rowing, Hiking, HighIntensityIntervalTraining, Dance, Basketball, Soccer, Tennis, Golf, StairClimbing, and more.

**Example**:
```typescript
const result = await Health.readSamples({
  dataType: 'workout',
  startDate: '2024-01-01T00:00:00Z',
  endDate: '2024-01-31T23:59:59Z',
  limit: 50
});

// Sample output:
// {
//   date: "2024-01-15",
//   type: "Running",
//   duration: 45,
//   distance: 5.23,
//   calories: 450,
//   source: "Apple Watch",
//   avgHeartRate: 145,
//   maxHeartRate: 175,
//   zones: { zone2: 10, zone3: 20, zone4: 15 }
// }
```

---

## 🔧 Methods

### isAvailable()

Check if health services are available on the current platform.

```typescript
Health.isAvailable(): Promise<AvailabilityResult>
```

**Returns**: `Promise<AvailabilityResult>`

**Example**:
```typescript
const result = await Health.isAvailable();

if (result.available) {
  console.log('Health services available on:', result.platform);
} else {
  console.log('Unavailable reason:', result.reason);
}
```

**Response Example**:
```typescript
{
  available: true,
  platform: 'ios' // or 'android'
}

// When unavailable:
{
  available: false,
  platform: 'android',
  reason: 'Health Connect is unavailable on this device.'
}
```

---

### requestAuthorization()

Request permission to read and/or write specific health data types. This will show the platform's native permission dialog.

```typescript
Health.requestAuthorization(options: AuthorizationOptions): Promise<AuthorizationStatus>
```

**Parameters**:
- `options.read` (optional): Array of data types you want to read
- `options.write` (optional): Array of data types you want to write

**Returns**: `Promise<AuthorizationStatus>`

**Example**:
```typescript
const status = await Health.requestAuthorization({
  read: ['steps', 'heartRate', 'sleep'],
  write: ['steps', 'weight']
});

console.log('Read authorized:', status.readAuthorized);
console.log('Read denied:', status.readDenied);
console.log('Write authorized:', status.writeAuthorized);
console.log('Write denied:', status.writeDenied);
```

**Response Example**:
```typescript
{
  readAuthorized: ['steps', 'heartRate'],
  readDenied: ['sleep'],
  writeAuthorized: ['steps', 'weight'],
  writeDenied: []
}
```

**Important Notes**:
- On **iOS**, the HealthKit API doesn't reveal whether the user granted or denied read permission (for privacy reasons). The `readAuthorized` array will contain all requested types, even if some were denied.
- On **Android**, Health Connect provides accurate permission status.
- You must call this method before reading or writing health data.

---

### checkAuthorization()

Check the current authorization status without prompting the user.

```typescript
Health.checkAuthorization(options: AuthorizationOptions): Promise<AuthorizationStatus>
```

**Parameters**: Same as `requestAuthorization()`

**Returns**: `Promise<AuthorizationStatus>`

**Example**:
```typescript
const status = await Health.checkAuthorization({
  read: ['steps', 'heartRate'],
  write: ['weight']
});

if (status.readAuthorized.includes('steps')) {
  // We have permission to read steps
  await readStepsData();
}
```

**Response Example**: Same structure as `requestAuthorization()`

---

### readSamples()

Read health samples for a specific data type within a time range.

```typescript
Health.readSamples(options: QueryOptions): Promise<ReadSamplesResult>
```

**Parameters**:
- `options.dataType` (required): The type of health data to retrieve
- `options.startDate` (optional): ISO 8601 start date (inclusive). Defaults to 24 hours ago
- `options.endDate` (optional): ISO 8601 end date (exclusive). Defaults to now
- `options.limit` (optional): Maximum number of samples to return. Defaults to 100
- `options.ascending` (optional): Sort results by start date ascending. Defaults to false (descending)

**Returns**: `Promise<ReadSamplesResult>`

**Example**:
```typescript
// Read last 7 days of step data
const result = await Health.readSamples({
  dataType: 'steps',
  startDate: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
  endDate: new Date().toISOString(),
  limit: 50,
  ascending: false
});

result.samples.forEach(sample => {
  console.log(`${sample.value} ${sample.unit} on ${sample.startDate}`);
});
```

**Response Example**:
```typescript
{
  samples: [
    {
      dataType: 'steps',
      value: 8543,
      unit: 'count',
      startDate: '2025-12-17T00:00:00.000Z',
      endDate: '2025-12-17T23:59:59.999Z',
      sourceName: 'Apple Watch',
      sourceId: 'com.apple.health'
    },
    {
      dataType: 'steps',
      value: 12032,
      unit: 'count',
      startDate: '2025-12-16T00:00:00.000Z',
      endDate: '2025-12-16T23:59:59.999Z',
      sourceName: 'iPhone',
      sourceId: 'com.apple.health'
    }
  ]
}
```

**Sleep Data Example**:
```typescript
const sleepResult = await Health.readSamples({
  dataType: 'sleep',
  startDate: '2025-12-16T00:00:00.000Z',
  endDate: '2025-12-17T00:00:00.000Z'
});

// Sleep samples include sleepState information
sleepResult.samples.forEach(sample => {
  console.log(`Sleep: ${sample.value} ${sample.unit}, State: ${sample.sleepState}`);
});
```

**Response Example for Sleep**:
```typescript
{
  samples: [
    {
      dataType: 'sleep',
      value: 450,
      unit: 'minute',
      startDate: '2025-12-16T22:30:00.000Z',
      endDate: '2025-12-17T06:00:00.000Z',
      sleepState: 'asleepDeep',
      sourceName: 'Sleep App'
    }
  ]
}
```

---

### saveSample()

Write a single health sample to the native health store.

```typescript
Health.saveSample(options: WriteSampleOptions): Promise<void>
```

**Parameters**:
- `options.dataType` (required): The type of health data to save
- `options.value` (required): The numeric value
- `options.unit` (optional): Unit override (must match the data type's expected unit)
- `options.startDate` (optional): ISO 8601 start date. Defaults to now
- `options.endDate` (optional): ISO 8601 end date. Defaults to startDate
- `options.metadata` (optional): Additional key-value metadata (platform support varies)

**Returns**: `Promise<void>`

**Example - Save Weight**:
```typescript
await Health.saveSample({
  dataType: 'weight',
  value: 72.5,
  startDate: new Date().toISOString()
});
```

**Example - Save Steps with Time Range**:
```typescript
const workoutStart = new Date('2025-12-17T10:00:00.000Z');
const workoutEnd = new Date('2025-12-17T11:30:00.000Z');

await Health.saveSample({
  dataType: 'steps',
  value: 5000,
  startDate: workoutStart.toISOString(),
  endDate: workoutEnd.toISOString(),
  metadata: {
    'workout': 'morning run',
    'location': 'park'
  }
});
```

**Example - Save Heart Rate**:
```typescript
await Health.saveSample({
  dataType: 'heartRate',
  value: 75,
  unit: 'bpm',
  startDate: new Date().toISOString()
});
```

**Unit Validation**: The plugin validates that the provided unit matches the expected unit for the data type. For example:
- `steps` expects `count`
- `distance` expects `meter`
- `calories` expects `kilocalorie`
- `heartRate` expects `bpm`
- `weight` expects `kilogram`

---

### getPluginVersion()

Get the current version of the native plugin.

```typescript
Health.getPluginVersion(): Promise<{ version: string }>
```

**Returns**: `Promise<{ version: string }>`

**Example**:
```typescript
const { version } = await Health.getPluginVersion();
console.log('Plugin version:', version);
```

---

## 💡 Common Usage Patterns

### 1. Displaying Daily Step Count

```typescript
async function getDailySteps() {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  
  const result = await Health.readSamples({
    dataType: 'steps',
    startDate: today.toISOString(),
    endDate: new Date().toISOString()
  });

  const totalSteps = result.samples.reduce((sum, sample) => sum + sample.value, 0);
  console.log('Steps today:', totalSteps);
  
  return totalSteps;
}
```

### 2. Weekly Activity Summary

```typescript
async function getWeeklySummary() {
  const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  
  const [steps, distance, calories] = await Promise.all([
    Health.readSamples({
      dataType: 'steps',
      startDate: weekAgo.toISOString(),
      limit: 500
    }),
    Health.readSamples({
      dataType: 'distance',
      startDate: weekAgo.toISOString(),
      limit: 500
    }),
    Health.readSamples({
      dataType: 'calories',
      startDate: weekAgo.toISOString(),
      limit: 500
    })
  ]);

  return {
    totalSteps: steps.samples.reduce((sum, s) => sum + s.value, 0),
    totalDistance: distance.samples.reduce((sum, s) => sum + s.value, 0),
    totalCalories: calories.samples.reduce((sum, s) => sum + s.value, 0)
  };
}
```

### 3. Logging Weight Over Time

```typescript
async function getWeightHistory(days: number = 30) {
  const startDate = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  
  const result = await Health.readSamples({
    dataType: 'weight',
    startDate: startDate.toISOString(),
    ascending: true
  });

  return result.samples.map(sample => ({
    date: new Date(sample.startDate).toLocaleDateString(),
    weight: sample.value,
    unit: sample.unit
  }));
}
```

### 4. Sleep Analysis

```typescript
async function getLastNightSleep() {
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  yesterday.setHours(18, 0, 0, 0); // Start from 6 PM yesterday
  
  const result = await Health.readSamples({
    dataType: 'sleep',
    startDate: yesterday.toISOString(),
    endDate: new Date().toISOString()
  });

  // Calculate total sleep time and breakdown by stage
  const sleepByStage: Record<string, number> = {};
  let totalSleep = 0;

  result.samples.forEach(sample => {
    const state = sample.sleepState || 'unknown';
    sleepByStage[state] = (sleepByStage[state] || 0) + sample.value;
    totalSleep += sample.value;
  });

  return {
    totalMinutes: totalSleep,
    totalHours: (totalSleep / 60).toFixed(1),
    breakdown: sleepByStage
  };
}
```

### 5. Recording a Workout

```typescript
async function recordWorkout() {
  const workoutStart = new Date(Date.now() - 45 * 60 * 1000); // 45 minutes ago
  const workoutEnd = new Date();

  // Save multiple metrics from the workout
  await Promise.all([
    Health.saveSample({
      dataType: 'steps',
      value: 4500,
      startDate: workoutStart.toISOString(),
      endDate: workoutEnd.toISOString()
    }),
    Health.saveSample({
      dataType: 'distance',
      value: 3500, // 3.5 km in meters
      startDate: workoutStart.toISOString(),
      endDate: workoutEnd.toISOString()
    }),
    Health.saveSample({
      dataType: 'calories',
      value: 320,
      startDate: workoutStart.toISOString(),
      endDate: workoutEnd.toISOString()
    })
  ]);

  console.log('Workout recorded successfully!');
}
```

---

## ⚠️ Error Handling

### Common Errors and Solutions

```typescript
async function safeHealthRead() {
  try {
    // Check availability first
    const availability = await Health.isAvailable();
    if (!availability.available) {
      throw new Error(`Health unavailable: ${availability.reason}`);
    }

    // Request authorization
    const authStatus = await Health.requestAuthorization({
      read: ['steps']
    });

    if (authStatus.readDenied.includes('steps')) {
      throw new Error('User denied permission to read steps');
    }

    // Read data
    const result = await Health.readSamples({
      dataType: 'steps',
      startDate: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
    });

    return result.samples;

  } catch (error) {
    console.error('Health data error:', error);
    
    // Handle specific error cases
    if (error.message.includes('unavailable')) {
      alert('Please install Health Connect (Android) or enable HealthKit (iOS)');
    } else if (error.message.includes('permission')) {
      alert('Please grant health data permissions in settings');
    } else if (error.message.includes('Unsupported data type')) {
      alert('This health metric is not supported on your device');
    } else {
      alert('Unable to access health data. Please try again.');
    }
    
    return [];
  }
}
```

### Error Types

| Error | Cause | Solution |
|-------|-------|----------|
| `Health data is not available` | HealthKit/Health Connect not available | Check device compatibility |
| `Unsupported data type` | Invalid dataType parameter | Use one of the supported data types |
| `dataType is required` | Missing required parameter | Provide dataType in options |
| `value is required` | Missing value for saveSample | Provide numeric value |
| `Invalid ISO 8601 date` | Malformed date string | Use proper ISO 8601 format: `new Date().toISOString()` |
| `endDate must be greater than startDate` | Invalid date range | Ensure endDate >= startDate |
| `Health Connect needs an update` | Outdated Health Connect app | Update Health Connect from Play Store |
| `Unsupported unit` | Wrong unit for data type | Use the correct unit or omit to use default |

---

## 🔒 Privacy & Security

### iOS Privacy Considerations

- **HealthKit data never leaves the device** unless explicitly shared by your app
- Apple's HealthKit restricts read authorization status for privacy—your app cannot definitively know if read permission was denied
- Always provide clear explanations in your usage description strings
- Consider implementing fallback flows if users deny permissions

### Android Privacy Considerations

- Health Connect provides transparent permission management
- Users can revoke permissions at any time through system settings
- Your app should handle permission changes gracefully
- Health Connect shows users which apps access their data

### Best Practices

1. **Request only what you need**: Don't request access to all data types if you only need steps
2. **Explain before asking**: Show UI explaining why you need health data before calling `requestAuthorization()`
3. **Handle denials gracefully**: Provide alternative functionality if permissions are denied
4. **Respect user privacy**: Don't store sensitive health data on external servers without explicit consent
5. **Test permission flows**: Test your app's behavior when permissions are denied or revoked

---

## 🐛 Known Limitations & Issues

### iOS Limitations

1. **Read Authorization Status**: HealthKit doesn't reveal whether users denied read permissions (privacy feature)
2. **Background Access**: Reading health data in the background requires additional setup with Background Modes capability
3. **Composite Types**: `mobility`, `activity`, `heart`, and `body` are iOS-only aggregate types that return data from multiple HealthKit sources
4. **Write Authorization**: Apps can only write data types they created or have explicit write permission for

### Android Limitations

1. **Health Connect Required**: Users must have the Health Connect app installed (available on Android 9+)
2. **Device Support**: Not all Android devices support Health Connect (mainly newer devices)
3. **Limited Data Types**: Android implementation supports fewer composite types than iOS
4. **API Level**: Requires minimum API level 28 (Android 9.0)

### General Limitations

1. **No Web Support**: This plugin does not work on web platforms (browser)
2. **Data Sync Delays**: Health data may take time to sync between devices/apps
3. **Source Variability**: Different apps and devices may report the same metrics differently
4. **Historical Data**: Very old data (>1 year) may not be available depending on device settings
5. **Unit Conversions**: The plugin uses specific units for each data type—unit conversion must be done in your app code

---

## 📱 Platform-Specific Notes

### iOS (HealthKit)

- Requires physical iOS device for testing (Simulator has limited support)
- Some health metrics require specific hardware (Apple Watch for certain heart rate measurements)
- Sleep data quality depends on the user's sleep tracking app (Apple Watch, third-party apps)
- HealthKit automatically aggregates data from multiple sources

### Android (Health Connect)

- Health Connect must be installed separately on devices with Android 13 or lower
- Android 14+ includes Health Connect as a system service
- Health Connect serves as a centralized hub for health data from multiple apps
- Not all Android OEMs enable Health Connect on their devices
- Users control which apps can access Health Connect through system settings

---

## 🧪 Testing

### Testing on iOS

1. Use a physical device (Simulator has limited HealthKit support)
2. Generate sample health data using the Health app or third-party apps
3. Test with Apple Watch if testing watch-specific metrics

### Testing on Android

1. Install Health Connect from the Play Store (if not pre-installed)
2. Use Health Connect's test data generator or third-party health apps
3. Test permission flows thoroughly—users can grant/deny per-data-type
4. Test on multiple Android versions (9, 10, 13, 14) for compatibility

---

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch
3. Make your changes with clear commit messages
4. Test on both iOS and Android
5. Submit a pull request

Please ensure your code follows the existing code style and includes appropriate error handling.

---

## 📄 License

This project is licensed under the **MPL-2.0 License** (Mozilla Public License 2.0).

See the [LICENSE](LICENSE) file for details.

---

## 🔗 Links

- **GitHub Repository**: [https://github.com/sandip-3008/capacitor-health](https://github.com/sandip-3008/capacitor-health)
- **npm Package**: [@interval-health/capacitor-health](https://www.npmjs.com/package/@interval-health/capacitor-health)
- **Issues & Bug Reports**: [GitHub Issues](https://github.com/sandip-3008/capacitor-health/issues)

---

## 📞 Support

For questions, issues, or feature requests:

1. Check the [documentation](#-api-reference) and [common patterns](#-common-usage-patterns)
2. Search [existing issues](https://github.com/sandip-3008/capacitor-health/issues)
3. Open a new issue with detailed information about your problem

**Note**: When reporting issues, please include:
- Platform (iOS/Android)
- OS version
- Plugin version
- Code sample demonstrating the issue
- Error messages or logs

---

## 📋 TypeScript Types

The plugin is written in TypeScript and includes full type definitions. Import types directly:

```typescript
import {
  Health,
  HealthDataType,
  HealthUnit,
  SleepState,
  AuthorizationOptions,
  AuthorizationStatus,
  QueryOptions,
  HealthSample,
  ReadSamplesResult,
  WriteSampleOptions
} from '@interval-health/capacitor-health';
```

---

**Made with ❤️ for the Capacitor community**
