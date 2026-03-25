import 'package:flutter/material.dart';

class BookStation extends StatefulWidget {
  const BookStation({super.key});

  @override
  State<BookStation> createState() => _BookStationState();
}

class _BookStationState extends State<BookStation> {
  // --- THEME COLORS (Matched to previous code) ---
  final Color _primaryColor = const Color(0xFF0253A4); // Royal Blue
  final Color _backgroundColor = const Color(0xFFF5F7FA);
  final Color _lightFillColor = const Color(0xFFE6EFF8); // Light Blue Fill

  // State variables for demo
  String? _selectedStation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Book Station',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // 1. SELECT CHARGING STATION CARD
            _buildSectionCard(
              title: 'Select Charging Station',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedStation,
                        hint: Text(
                          'Choose a station...',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        isExpanded: true,
                        icon: const Icon(Icons.expand_more),
                        items: ['Station A', 'Station B', 'Station C']
                            .map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedStation = val),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.flash_on, color: _primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Fast charging available',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. SELECT TIME PERIOD CARD
            _buildSectionCard(
              title: 'Select Time Period',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Start Date & Time'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildInputField('mm/dd/yyyy', null)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildInputField('--:-- --', Icons.calendar_today_outlined)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('End Date & Time'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildInputField('mm/dd/yyyy', null)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildInputField('--:-- --', Icons.calendar_today_outlined)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.1), // Light Blue bg
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Duration',
                          style: TextStyle(
                            color: _primaryColor, // Blue Text
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '2h 30m',
                          style: TextStyle(
                            color: _primaryColor, // Blue Text
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 3. PRICING DETAILS CARD
            _buildSectionCard(
              title: 'Pricing Details',
              child: Column(
                children: [
                  _buildPriceRow('Hourly Rate', 'Rs.12.50/hr'),
                  const SizedBox(height: 12),
                  _buildPriceRow('Duration', '2.5 hours'),
                  const SizedBox(height: 16),
                  Divider(color: Colors.grey.shade200),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Cost',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                      const Text(
                        'Rs.31.25',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Info Box (Replaced Green with Blue theme)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _lightFillColor, // Light Blue Fill
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info, color: _primaryColor, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Deposit Required',
                              style: TextStyle(
                                color: _primaryColor, // Dark Blue Text
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            style: TextStyle(color: _primaryColor, fontSize: 13, height: 1.4),
                            children: [
                              const TextSpan(
                                text: '10% of total cost- ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const TextSpan(
                                text: 'You\'ll pay Rs.3.13 now to secure your booking',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 4. CONFIRM BUTTON
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor, // Royal Blue
                  elevation: 4,
                  shadowColor: _primaryColor.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Confirm Booking - Pay Rs.3.13',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Remaining balance due upon arrival',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.grey.shade600,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildInputField(String hint, IconData? suffixIcon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            hint,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
            ),
          ),
          if (suffixIcon != null)
            Icon(suffixIcon, color: Colors.black87, size: 20),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}