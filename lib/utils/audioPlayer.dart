import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class AudioPlayerTile extends StatefulWidget {
  final String url;
  final DateTime timestamp;

  const AudioPlayerTile({super.key, required this.url, required this.timestamp});

  @override
  _AudioPlayerTileState createState() => _AudioPlayerTileState();
}

class _AudioPlayerTileState extends State<AudioPlayerTile> {
  late AudioPlayer _audioPlayer;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _audioPlayer.onPositionChanged.listen((newPosition) {
      setState(() {
        _position = newPosition;
      });
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      setState(() {
        _totalDuration = newDuration;
      });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.timestamp.toString()),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _position.inSeconds.toDouble(),
                      max: _totalDuration.inSeconds.toDouble(),
                      onChanged: (value) async {
                        final newPosition = Duration(seconds: value.toInt());
                        await _audioPlayer.seek(newPosition);
                      },
                    ),
                  ),
                  Text(
                    '${_position.inMinutes}:${(_position.inSeconds % 60).toString().padLeft(2, '0')} / ${_totalDuration.inMinutes}:${(_totalDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () async {
                      await _audioPlayer.play(UrlSource(widget.url)); // Play the audio file
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.pause),
                    onPressed: () async {
                      await _audioPlayer.pause(); // Pause the audio file
                    },
                  ),
                ],
              ),
                            SizedBox(height: 1, child: Container(color: Colors.black)), // Add a small space between the rows

            ],
          ),
        ],
        
      ),
    );
  }
}