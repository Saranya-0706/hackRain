import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

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
        ),
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
  TimeOfDay? selectedTime;
  String result = "";
  final MapController mapController = MapController();

  final TextEditingController searchController = TextEditingController();
  bool isPredictEnabled() =>
      selectedDate != null && selectedTime != null && selectedLocation != null;


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
    if (date != null) setState(() => selectedDate = date);
  }

  // Pick Time
  Future<void> pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) setState(() => selectedTime = time);
  }

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

  // Dummy backend call
  Future<void> getPrediction() async {
    final eventDateTime = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
      selectedTime!.hour,
      selectedTime!.minute,
    ).toIso8601String();

    final url = Uri.parse("http://10.0.2.2:8000/predict"); // Replace with backend

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "latitude": selectedLocation.latitude,
          "longitude": selectedLocation.longitude,
          "datetime": eventDateTime,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          result = "🌧 Prediction: ${data['prediction']}";
        });
      } else {
        setState(() {
          result = "❌ Error: ${response.body}";
        });
      }
    } catch (e) {
      setState(() {
        result = "❌ Error connecting to backend.";
      });
    }
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
              child: Column(
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
                  ElevatedButton(
                    onPressed: pickTime,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primCol,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(selectedTime == null
                        ? "Select Time"
                        : "${selectedTime!.hour}:${selectedTime!.minute.toString().padLeft(2, '0')}"),
                  ),
                  const SizedBox(height: 15),

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
                  Text(
                    result,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
