import 'package:flutter/material.dart';
import '../widgets/app_scaffold.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'About Us',
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero banner
            Stack(
              children: [
                Container(
                  height: 200,
                  width: double.infinity,
                  color: Colors.grey.shade200,
                  child: Center(
                    child: Icon(
                      Icons.image,
                      size: 50,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Our Journey',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Connecting devotees with authentic spiritual services since 2020',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Our Story
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Our Story',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8B0000),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PujaKaro was founded with a simple mission: to make authentic spiritual services accessible to everyone, regardless of their location. Our journey began when our founder, Ramesh Ji, recognized the challenges faced by devotees in finding reliable pandits and obtaining quality puja materials.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Color(0xFF5F4B32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'What started as a small initiative to connect local pandits with devotees has now grown into a comprehensive platform offering a wide range of spiritual services, from puja bookings to astrology consultations, all delivered with devotion and authenticity.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Color(0xFF5F4B32),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Our Mission
                  const Text(
                    'Our Mission',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8B0000),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMissionItem(
                    icon: Icons.check_circle_outline,
                    title: 'Authenticity',
                    description: 'Provide genuine spiritual services performed by verified pandits following traditional rituals.',
                  ),
                  _buildMissionItem(
                    icon: Icons.check_circle_outline,
                    title: 'Accessibility',
                    description: 'Make spiritual practices accessible to devotees worldwide, bridging geographical barriers.',
                  ),
                  _buildMissionItem(
                    icon: Icons.check_circle_outline,
                    title: 'Education',
                    description: 'Spread knowledge about Hindu rituals, their significance, and spiritual practices.',
                  ),
                  _buildMissionItem(
                    icon: Icons.check_circle_outline,
                    title: 'Community',
                    description: 'Build a global community of devotees connected through shared spiritual values.',
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Our Team
                  const Text(
                    'Meet Our Team',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8B0000),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            
            // Team members
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildTeamMember(
                    name: 'Ramesh Sharma',
                    role: 'Founder & CEO',
                    description: 'With over 20 years of experience in spiritual practices, Ramesh Ji brings deep knowledge and passion to PujaKaro.',
                  ),
                  _buildTeamMember(
                    name: 'Priya Patel',
                    role: 'Head of Operations',
                    description: 'Priya ensures that all services are delivered with precision and devotion, maintaining our quality standards.',
                  ),
                  _buildTeamMember(
                    name: 'Dr. Anand Joshi',
                    role: 'Chief Astrologer',
                    description: 'A renowned astrologer with expertise in Vedic astrology, Dr. Joshi leads our astrology services.',
                  ),
                  _buildTeamMember(
                    name: 'Lakshmi Rao',
                    role: 'Customer Experience',
                    description: 'Dedicated to ensuring every devotee has a meaningful and satisfying experience with our services.',
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Our Values
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Our Values',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8B0000),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildValueCard(
                    icon: Icons.verified,
                    title: 'Authenticity',
                    description: 'We are committed to preserving the authenticity of ancient rituals while making them accessible in the modern world.',
                    color: const Color(0xFFFB9548),
                  ),
                  _buildValueCard(
                    icon: Icons.favorite,
                    title: 'Devotion',
                    description: 'Every service we offer is performed with utmost devotion and respect for spiritual traditions.',
                    color: const Color(0xFF8B0000),
                  ),
                  _buildValueCard(
                    icon: Icons.people,
                    title: 'Community',
                    description: 'We believe in building a global community united by shared spiritual values and practices.',
                    color: const Color(0xFF317BEA),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Testimonials
                  const Text(
                    'What Our Devotees Say',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8B0000),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildTestimonial(
                    name: 'Anjali Mehta',
                    location: 'Mumbai, India',
                    testimonial: 'PujaKaro has made it incredibly convenient for me to arrange pujas even when I\'m traveling. The pandits are knowledgeable and the service is always on time.',
                  ),
                  _buildTestimonial(
                    name: 'Rajesh Kumar',
                    location: 'New Jersey, USA',
                    testimonial: 'Living abroad, it was difficult to find authentic puja services until I discovered PujaKaro. Now I can maintain my spiritual practices with ease.',
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Contact Us CTA
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6E5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFB9548).withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Have Questions?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8B0000),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'We\'d love to hear from you. Reach out to us with any questions, suggestions, or feedback.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF5F4B32),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/contact');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFB9548),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Contact Us',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
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
    );
  }
  
  Widget _buildMissionItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFFFB9548),
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5F4B32),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF5F4B32),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTeamMember({
    required String name,
    required String role,
    required String description,
  }) {
    return Container(
      width: 250,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: const Color(0xFFFFF6E5),
            child: Text(
              name.split(' ').map((e) => e[0]).join(''),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF8B0000),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5F4B32),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            role,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFFFB9548),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF5F4B32),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildValueCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5F4B32),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF5F4B32),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTestimonial({
    required String name,
    required String location,
    required String testimonial,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.format_quote,
                color: Color(0xFFFB9548),
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            testimonial,
            style: const TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: Color(0xFF5F4B32),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFFFF6E5),
                radius: 20,
                child: Text(
                  name[0],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8B0000),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5F4B32),
                    ),
                  ),
                  Text(
                    location,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
