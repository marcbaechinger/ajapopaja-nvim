rows = [
    {"name": "Marc", "profession": "Software engineer", "nationality": "Switzerland"},
    {"name": "Marc", "profession": "Software engineer", "nationality": "Switzerland"},
]


def create_html_table(rows):
    if not rows:
        return ""

    headers = list(rows[0].keys())

    html = "<table style='width:100%'>\n"
    html += "  <thead style='background-color:#f2f2f2'>\n"
    html += "    <tr >\n"
    for header in headers:
        html += f"      <th >{header}</th>\n"
    html += "    </tr>\n"
    html += "  </thead>\n"
    html += "  <tbody>\n"
    for i, row in enumerate(rows):
        if i % 2 == 0:
            row_style = "background-color:#f2f2f2;"
        else:
            row_style = ""
        html += f"    <tr style='{row_style}'>\n"
        for header in headers:
            html += f"      <td>{row[header]}</td>\n"
        html += "    </tr>\n"
    html += "  </tbody>\n"
    html += "</table>"

    return html


def regression(data: list[list[float]]) -> float:
    if not data:
        return 0.0

    n = len(data)
    x_sum = sum(row[0] for row in data)
    y_sum = sum(row[1] for row in data)
    x_mean = x_sum / n
    y_mean = y_sum / n

    numerator = sum((row[0] - x_mean) * (row[1] - y_mean) for row in data)
    denominator = sum((row[0] - x_mean) ** 2 for row in data)

    if denominator == 0:
        return 0.0

    return numerator / denominator


def count_by_country(sorted_list_of_countries: list[str], country: str) -> int:
    if not sorted_list_of_countries:
        return 0

    # Find the first occurrence of the country
    left = 0
    right = len(sorted_list_of_countries) - 1
    first_occurrence = -1

    while left <= right:
        mid = (left + right) // 2
        if sorted_list_of_countries[mid] == country:
            first_occurrence = mid
            right = mid - 1  # Continue searching in the left half
        elif sorted_list_of_countries[mid] < country:
            left = mid + 1
        else:
            right = mid - 1

    if first_occurrence == -1:
        return 0

    # Find the last occurrence of the country
    left = first_occurrence
    right = len(sorted_list_of_countries) - 1
    last_occurrence = first_occurrence

    while left <= right:
        mid = (left + right) // 2
        if sorted_list_of_countries[mid] == country:
            last_occurrence = mid
            left = mid + 1  # Continue searching in the right half
        elif sorted_list_of_countries[mid] < country:
            left = mid + 1
        else:
            right = mid - 1

    # Return the count
    return last_occurrence - first_occurrence + 1


def distance_on_surface_of_earth(lat1, lon1, lat2, lon2) -> int:
    import math

    # Earth's radius in kilometers
    R = 6371

    # Convert degrees to radians
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)

    # Calculate differences
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad

    # Haversine formula
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2) ** 2
    )
    c = 2 * math.asin(math.sqrt(a))

    # Distance in kilometers
    distance = R * c

    return round(distance)


def merge_sort(
    sorted_strings_1: list[str],
    sorted_strings_2: list[str],
    input_sort_order_descending: bool,
) -> list[str]:
    result = []
    i, j = 0, 0

    # Merge the two sorted lists
    while i < len(sorted_strings_1) and j < len(sorted_strings_2):
        if input_sort_order_descending:
            if sorted_strings_1[i] >= sorted_strings_2[j]:
                result.append(sorted_strings_1[i])
                i += 1
            else:
                result.append(sorted_strings_2[j])
                j += 1
        else:
            if sorted_strings_1[i] <= sorted_strings_2[j]:
                result.append(sorted_strings_1[i])
                i += 1
            else:
                result.append(sorted_strings_2[j])
                j += 1

    # Add remaining elements
    while i < len(sorted_strings_1):
        result.append(sorted_strings_1[i])
        i += 1

    while j < len(sorted_strings_2):
        result.append(sorted_strings_2[j])
        j += 1

    return result
