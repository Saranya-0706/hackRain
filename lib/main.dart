import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Will it Rain on My Parade?',
      theme: ThemeData(
        primaryColor: Colors.lightBlue[400],
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: Colors.lightBlue[400],
          secondary: Colors.blueAccent,
        ),useMaterial3:  true,
      ),
      home: const PredictionScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();

}

class _PredictionScreenState extends State<PredictionScreen> {
  Color? primCol = Colors.lightBlue[400];
  Color? secCol = Colors.blueAccent;
  String? locationName;
  LatLng selectedLocation = LatLng(28.6139, 77.2090); //Default:Delhi
  double zoom = 12.0;
  DateTime? selectedDate;
  //TimeOfDay? selectedTime;
  String result = "";
  double? avgTemp;
  double? avgRain;
  double? avgWind;
  double? avgHumidity;
  int selectedChartIndex = 0; // 0-temp, 1-rain, 2-wind, 3-humidity
  List<Map<String, dynamic>> chartData = [];
  final MapController mapController = MapController();

  final TextEditingController searchController = TextEditingController();
  bool isPredictEnabled() =>
      selectedDate != null && selectedLocation != null;


  @override
  void initState() {
    super.initState();
     mapController.mapEventStream.listen((event) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      mapController.move(selectedLocation, zoom);
      updateLocationName(selectedLocation);
    });
  }

  // Pick Date
  Future<void> pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (date != null)
      setState(() => selectedDate = date);
    clearPreviousPrediction();
  }

  // Pick Time
  // Future<void> pickTime() async {
  //   final time = await showTimePicker(
  //     context: context,
  //     initialTime: TimeOfDay.now(),
  //   );
  //   if (time != null) setState(() => selectedTime = time);
  // }

  // Get Current Location
  Future<void> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      selectedLocation = LatLng(pos.latitude, pos.longitude);
      mapController.move(selectedLocation, 12);
    });
    updateLocationName(selectedLocation);
    searchController.clear();
  }

  // Search Location -> Nominatim
  Future<void> searchLocation(String query) async {
    final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1");
    try {
      final response = await http.get(url, headers: {
        "User-Agent": "Flutter App - Rain Prediction"
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          setState(() {
            selectedLocation = LatLng(lat, lon);
            clearPreviousPrediction();
            mapController.move(selectedLocation, 12);
          });
          updateLocationName(selectedLocation);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Location not found.")));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Error fetching location.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error connecting to search API.")));
    }

  }

  //reverse geoCoding -> Nominatim
  Future<void> updateLocationName(LatLng location) async {
    final url = Uri.parse(
        "https://nominatim.openstreetmap.org/reverse?lat=${location.latitude}&lon=${location.longitude}&format=json&zoom=10&addressdetails=1");
    try {
      final response = await http.get(url, headers: {
        "User-Agent": "Flutter App - Rain Prediction"
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String displayName = data['display_name'] ?? "Unknown location";
        setState(() {
          locationName = displayName;
        });
      } else {
        setState(() {
          locationName = "Unknown location";
        });
      }
    } catch (e) {
      setState(() {
        locationName = "Error fetching location";
      });
    }
  }

  //backend call
  Future<void> getPrediction() async {
    setState(() {
      result = "⏳ Fetching predictions for nearby days...";
      avgTemp = avgRain = avgWind = avgHumidity = null;
      chartData.clear();
    });

    final url = Uri.parse("http://127.0.0.1:8000/api/weather_risk");
    final lat = selectedLocation.latitude;
    final lon = selectedLocation.longitude;

    try {

      DateTime base = selectedDate!;
      List<DateTime> dateList = List.generate(7, (i) => base.add(Duration(days: i - 3)));

      //api callas
      List<Future<http.Response>> requests = dateList.map((date) {
        return http.post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "lat": lat,
            "lon": lon,
            "start_year": 2020,
            "end_year": 2024,
          }),
        );
      }).toList();

      List<http.Response> responses = await Future.wait(requests);

      List<Map<String, dynamic>> tempData = [];

      for (int i = 0; i < responses.length; i++) {
        var response = responses[i];
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final stats = data["result"];
          tempData.add({
            "date": dateList[i],
            "temp": stats["avg_temp_C"]?.toDouble() ?? 0.0,
            "rain": stats["avg_rain_mm"]?.toDouble() ?? 0.0,
            "wind": stats["avg_wind_kmh"]?.toDouble() ?? 0.0,
            "humidity": stats["avg_humidity_pct"]?.toDouble() ?? 0.0,
          });
        }
      }

      if (tempData.isNotEmpty) {
        final currentDay = tempData[2]; // middle = selected date

        setState(() {
          chartData = tempData;
          avgTemp = currentDay["temp"];
          avgRain = currentDay["rain"];
          avgWind = currentDay["wind"];
          avgHumidity = currentDay["humidity"];
          result = "success";
        });
      } else {
        setState(() => result = "❌ No valid responses from backend");
      }
    } catch (e) {
      setState(() => result = "❌ Error: $e");
    }
  }


  void clearPreviousPrediction() {
    setState(() {
      result = "";
      avgTemp = avgRain = avgWind = avgHumidity = null;
    });
  }

  //o/p card ui
  Widget _buildStatCard(IconData icon, String value, String label, Color color) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: const Offset(2, 3),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.4), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    if (chartData.isEmpty) {
      return const Text("No data available for nearby days.");
    }

    List<BarChartGroupData> groups = [];
    for (int i = 0; i < chartData.length; i++) {
      double value;
      switch (selectedChartIndex) {
        case 0: value = chartData[i]['temp']; break;
        case 1: value = chartData[i]['rain']; break;
        case 2: value = chartData[i]['wind']; break;
        case 3: value = chartData[i]['humidity']; break;
        default: value = 0;
      }

      final date = chartData[i]['date'] as DateTime;
      bool isSelected = date.day == selectedDate?.day &&
          date.month == selectedDate?.month;

      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: value,
              color: isSelected ? Colors.green : Colors.blueAccent,
              width: 18,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    String unit = ["°C", "mm", "km/h", "%"][selectedChartIndex];
    String label = ["Temperature", "Rainfall", "Wind Speed", "Humidity"][selectedChartIndex];

    return Card(
      elevation: 3,
      color: Colors.white,
      surfaceTintColor: primCol,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 5,
              alignment: WrapAlignment.center,
              children: List.generate(4, (i) {
                List<String> labels = ["Temp", "Rain", "Wind", "Humidity"];
                return ChoiceChip(
                  label: Text(labels[i]),
                  selected: selectedChartIndex == i,
                  onSelected: (_) => setState(() => selectedChartIndex = i),
                  selectedColor: Colors.lightBlue[300],
                  labelStyle: TextStyle(
                    color: selectedChartIndex == i ? Colors.white : Colors.black,
                  ),
                  backgroundColor: Colors.grey[200],
                );
              }),
            ),
            const SizedBox(height: 18),
            Text("$label ($unit)",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[700])),

            const SizedBox(height: 18),

            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index < 0 || index >= chartData.length) {
                            return const SizedBox();
                          }
                          DateTime d = chartData[index]['date'];
                          return Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              "${d.day}/${d.month}",
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: groups,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Will it Rain on My Parade?"),
        backgroundColor: Colors.lightBlue[400],
      ),
      body: Row(
        children: [
           Expanded(
            flex: 4,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                //center: selectedLocation,
                //zoom: zoom,
                onTap: (tapPoint, point) {
                  setState(() {
                    selectedLocation = point;
                    clearPreviousPrediction();
                  });
                  updateLocationName(point);
                  searchController.clear();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                  "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: const ['a', 'b', 'c'],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: selectedLocation,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
                // Zoom Control
                Positioned(
                  left: 10,
                  top: 0,
                  bottom: 0,
                  child: Center(child:
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    IconButton(
                      icon: const Icon(Icons.add_circle, size: 32),
                      onPressed: () {
                        setState(() {
                          zoom = (zoom + 1).clamp(1, 18);
                          mapController.move(selectedLocation, zoom);
                        });
                      },
                      color: primCol,
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle, size: 32),
                      onPressed: () {
                        setState(() {
                          zoom = (zoom - 1).clamp(1, 18);
                          mapController.move(selectedLocation, zoom);
                        });
                      },
                      color: primCol,
                    ),
                  ],
                ),),),
              ],
            ),
          ),

          // Right: Controls Column
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child:
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height), child:
                Column(
                children: [
                  // Search Bar
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search place...",
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () {
                          final query = searchController.text.trim();
                          if (query.isNotEmpty) {
                            searchLocation(query);
                          }
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Date Picker
                  ElevatedButton(
                    onPressed: pickDate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primCol,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(selectedDate == null
                        ? "Select Date"
                        : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"),
                  ),
                  const SizedBox(height: 10),

                  // Time Picker
                  // ElevatedButton(
                  //   onPressed: pickTime,
                  //   style: ElevatedButton.styleFrom(
                  //     backgroundColor: primCol,
                  //     foregroundColor: Colors.white,
                  //     shape: RoundedRectangleBorder(
                  //         borderRadius: BorderRadius.circular(8)),
                  //     minimumSize: const Size.fromHeight(50),
                  //   ),
                  //   child: Text(selectedTime == null
                  //       ? "Select Time"
                  //       : "${selectedTime!.hour}:${selectedTime!.minute.toString().padLeft(2, '0')}"),
                  // ),
                  // const SizedBox(height: 15),

                  // Selected Location Text
                  ElevatedButton(
                    onPressed: (){} ,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primCol,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(
                      locationName != null
                          ? "Selected Location:\n$locationName"
                          : "Selected Location:\n${selectedLocation.latitude.toStringAsFixed(5)}, ${selectedLocation.longitude.toStringAsFixed(5)}",
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Current Location Button
                  ElevatedButton.icon(
                    onPressed: getCurrentLocation,
                    icon: const Icon(Icons.my_location, color: Colors.white),
                    label: const Text("Use Current Location"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primCol,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Predict Rainfall Button
                  ElevatedButton(
                    onPressed: isPredictEnabled() ? getPrediction : null,
                    child: const Text(
                      "Predict Rainfall",
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      disabledBackgroundColor: Colors.green[300],
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Prediction Result
                  if (result.startsWith("⏳"))...[
                    const Padding(
                      padding: EdgeInsets.only(top: 30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  ],
                  if (result == "success") ...[
                    const SizedBox(height: 10),
                    Text(
                      "🌦 Weather ForeCast",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primCol,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 15,
                      runSpacing: 15,
                      children: [
                        _buildStatCard(Icons.thermostat, "${avgTemp!.toStringAsFixed(1)} °C", "Temperature", Colors.orangeAccent),
                        _buildStatCard(Icons.water_drop, "${avgRain!.toStringAsFixed(1)} mm", "Rainfall", Colors.blueAccent),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Wrap(
                      spacing: 15,
                      runSpacing: 15,
                      children: [
                        _buildStatCard(Icons.cloud, "${avgHumidity!.toStringAsFixed(0)}%", "Humidity", Colors.indigoAccent),
                        _buildStatCard(Icons.air, "${avgWind!.toStringAsFixed(1)} km/h", "Wind Speed", Colors.lightBlueAccent),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(
                      "📅 Nearby Dates Forecast",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primCol,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildBarChart(),
                  ]
                  else ...[
                    const SizedBox(height: 15),
                    Text(
                    result,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
